import Foundation

final class TranscriptionEngine {
    private let shortSeconds: Double = 0.6
    private let shortOverlapSeconds: Double = 0.2
    private let longSeconds: Double = 2.5
    private let longOverlapSeconds: Double = 0.5
    private let sampleRate: Double = 16_000

    private var shortBuffer: [Float] = []
    private var longBuffer: [Float] = []

    private let queue = DispatchQueue(label: "whisper.queue", qos: .userInitiated)

    private var stableText = ""
    private var currentText = ""
    private var displayedText = ""
    private var lastUIUpdate = Date.distantPast

    private let minUIInterval: TimeInterval = 0.1
    private let speechRMSFloor: Float = 0.0002
    private let finalizeRMSFloor: Float = 0.0006

    var onPartial: ((String) -> Void)?
    var onRefined: ((String) -> Void)?

    private let whisperManager: WhisperManager

    init(whisperManager: WhisperManager) {
        self.whisperManager = whisperManager
    }

    func reset() {
        shortBuffer.removeAll(keepingCapacity: true)
        longBuffer.removeAll(keepingCapacity: true)
        stableText = ""
        currentText = ""
        displayedText = ""
        lastUIUpdate = .distantPast
    }

    func append(samples: [Float]) {
        queue.async {
            self.shortBuffer.append(contentsOf: samples)
            self.longBuffer.append(contentsOf: samples)

            self.runFastLoopIfNeeded()
            self.runSlowLoopIfNeeded()
        }
    }

    func finalize(completion: @escaping (String) -> Void) {
        queue.async {
            var finalText = self.currentText
            if !self.longBuffer.isEmpty,
               self.rms(self.longBuffer) >= self.finalizeRMSFloor,
               let refined = self.whisperManager.transcribe(samples: self.longBuffer),
               !refined.isEmpty {
                self.applyRefined(refined)
                finalText = self.currentText
            }
            completion(finalText)
            self.reset()
        }
    }

    private func runFastLoopIfNeeded() {
        let target = Int(shortSeconds * sampleRate)
        let overlap = Int(shortOverlapSeconds * sampleRate)
        guard shortBuffer.count >= target else { return }
        guard rms(shortBuffer) >= speechRMSFloor else {
            shortBuffer = Array(shortBuffer.suffix(overlap))
            return
        }

        let chunk = Array(shortBuffer.prefix(target))
        if let partialText = whisperManager.transcribe(samples: chunk), !partialText.isEmpty {
            applyPartial(partialText)
        }
        shortBuffer = Array(shortBuffer.suffix(overlap))
    }

    private func runSlowLoopIfNeeded() {
        let target = Int(longSeconds * sampleRate)
        let overlap = Int(longOverlapSeconds * sampleRate)
        guard longBuffer.count >= target else { return }
        guard rms(longBuffer) >= speechRMSFloor else {
            longBuffer = Array(longBuffer.suffix(overlap))
            return
        }

        let chunk = Array(longBuffer.prefix(target))
        if let refinedText = whisperManager.transcribe(samples: chunk), !refinedText.isEmpty {
            applyRefined(refinedText)
        }
        longBuffer = Array(longBuffer.suffix(overlap))
    }

    private func applyPartial(_ partialText: String) {
        let lcp = longestCommonPrefix(stableText, partialText)
        let suffix = String(partialText.dropFirst(lcp.count))
        guard suffix.count > 2 else { return }

        currentText = stableText + suffix
        emitIfNeeded(isRefined: false)
    }

    private func applyRefined(_ refinedText: String) {
        let refined = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refined.isEmpty else { return }

        if stableText.isEmpty {
            stableText = refined
            currentText = refined
            emitIfNeeded(isRefined: true)
            return
        }

        let stable = stableText.trimmingCharacters(in: .whitespacesAndNewlines)
        if refined.count + 2 < stable.count && similarity(stable, refined) < 0.35 {
            // Treat short, low-overlap refined output as a new phrase after a pause.
            stableText = stable + " " + refined
        } else {
            stableText = refined
        }
        currentText = stableText
        emitIfNeeded(isRefined: true)
    }

    private func emitIfNeeded(isRefined: Bool) {
        let diff = abs(currentText.count - displayedText.count)
        guard isRefined || diff >= 2 else { return }

        let now = Date()
        guard isRefined || now.timeIntervalSince(lastUIUpdate) >= minUIInterval else { return }

        displayedText = currentText
        lastUIUpdate = now

        if isRefined {
            onRefined?(currentText)
        } else {
            onPartial?(currentText)
        }
    }

    private func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float.zero) { $0 + ($1 * $1) }
        return sqrt(sum / Float(samples.count))
    }

    private func similarity(_ a: String, _ b: String) -> Double {
        let sa = Set(a.lowercased().split(separator: " "))
        let sb = Set(b.lowercased().split(separator: " "))
        if sa.isEmpty && sb.isEmpty { return 1.0 }
        let common = sa.intersection(sb).count
        let denom = max(sa.count, sb.count)
        return denom == 0 ? 1.0 : Double(common) / Double(denom)
    }

    func longestCommonPrefix(_ a: String, _ b: String) -> String {
        var idxA = a.startIndex
        var idxB = b.startIndex
        while idxA < a.endIndex && idxB < b.endIndex && a[idxA] == b[idxB] {
            idxA = a.index(after: idxA)
            idxB = b.index(after: idxB)
        }
        return String(a[..<idxA])
    }
}
