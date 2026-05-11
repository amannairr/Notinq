import AVFoundation
import Foundation

final class AudioStreamManager {
    private let engine = AVAudioEngine()
    private let converter: AVAudioConverter
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private let queue = DispatchQueue(label: "audio.stream.queue", qos: .userInitiated)

    var onSamples: (([Float]) -> Void)?

    init?() {
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return nil }
        self.converter = converter
    }

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.queue.async {
                self?.consume(buffer: buffer)
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func consume(buffer: AVAudioPCMBuffer) {
        if let passthrough = passthroughSamplesIfAlreadyTarget(buffer: buffer), !passthrough.isEmpty {
            onSamples?(passthrough)
            return
        }

        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate) + 16)
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var error: NSError?
        var consumed = false

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
        guard error == nil else { return }
        guard status == .haveData || status == .inputRanDry else { return }

        if let channelData = converted.floatChannelData?[0], converted.frameLength > 0 {
            let count = Int(converted.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: count))
            if !samples.isEmpty {
                onSamples?(samples)
                return
            }
        }

        // Fallback for devices where converter yields zero frames in real-time callbacks.
        let fallback = downmixAndResampleToTarget(buffer: buffer)
        if !fallback.isEmpty {
            onSamples?(fallback)
        }
    }

    private func passthroughSamplesIfAlreadyTarget(buffer: AVAudioPCMBuffer) -> [Float]? {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              buffer.format.channelCount == 1,
              abs(buffer.format.sampleRate - targetFormat.sampleRate) < 0.5,
              let channelData = buffer.floatChannelData?[0] else { return nil }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: channelData, count: count))
    }

    private func downmixAndResampleToTarget(buffer: AVAudioPCMBuffer) -> [Float] {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let channelData = buffer.floatChannelData else { return [] }

        let channels = Int(buffer.format.channelCount)
        let inCount = Int(buffer.frameLength)
        guard channels > 0, inCount > 0 else { return [] }

        var mono = Array(repeating: Float.zero, count: inCount)
        for ch in 0..<channels {
            let ptr = channelData[ch]
            for i in 0..<inCount {
                mono[i] += ptr[i]
            }
        }
        let invChannels = 1.0 / Float(channels)
        for i in 0..<inCount {
            mono[i] *= invChannels
        }

        let inRate = buffer.format.sampleRate
        if abs(inRate - targetFormat.sampleRate) < 0.5 {
            return mono
        }

        let ratio = targetFormat.sampleRate / inRate
        let outCount = max(1, Int(Double(inCount) * ratio))
        var out = Array(repeating: Float.zero, count: outCount)
        for i in 0..<outCount {
            let srcPos = Double(i) / ratio
            let lo = Int(srcPos)
            let hi = min(lo + 1, inCount - 1)
            let t = Float(srcPos - Double(lo))
            out[i] = mono[lo] * (1 - t) + mono[hi] * t
        }
        return out
    }
}
