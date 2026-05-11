import Foundation

@_silgen_name("PLWhisperBackendAvailable")
private func PLWhisperBackendAvailable() -> Bool

@_silgen_name("PLWhisperCreate")
private func PLWhisperCreate(_ modelPath: UnsafePointer<CChar>?, _ threads: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("PLWhisperIsReady")
private func PLWhisperIsReady(_ handle: UnsafeMutableRawPointer?) -> Bool

@_silgen_name("PLWhisperTranscribe")
private func PLWhisperTranscribe(_ handle: UnsafeMutableRawPointer?, _ pcm: UnsafePointer<Float>?, _ nSamples: Int32) -> UnsafeMutablePointer<CChar>?

@_silgen_name("PLWhisperDestroy")
private func PLWhisperDestroy(_ handle: UnsafeMutableRawPointer?)

@_silgen_name("PLWhisperFreeCString")
private func PLWhisperFreeCString(_ ptr: UnsafeMutablePointer<CChar>?)

final class WhisperManager {
    private var handle: UnsafeMutableRawPointer?
    private let queue = DispatchQueue(label: "whisper.serial.queue", qos: .userInitiated)

    static var isBackendAvailable: Bool {
        PLWhisperBackendAvailable()
    }

    init?(modelPath: String, threads: Int = 8) {
        let created: UnsafeMutableRawPointer? = modelPath.withCString { cString in
            PLWhisperCreate(cString, Int32(max(1, threads)))
        }

        guard let created, PLWhisperIsReady(created) else {
            if let created {
                PLWhisperDestroy(created)
            }
            return nil
        }

        self.handle = created
    }

    func transcribe(samples: [Float]) -> String? {
        queue.sync {
            guard let handle, !samples.isEmpty else { return nil }
            return samples.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return nil }
                guard let cString = PLWhisperTranscribe(handle, base, Int32(buffer.count)) else {
                    return nil
                }
                defer { PLWhisperFreeCString(cString) }
                return String(cString: cString)
            }
        }
    }

    func shutdown() {
        queue.sync {
            if let handle {
                PLWhisperDestroy(handle)
                self.handle = nil
            }
        }
    }

    deinit {
        shutdown()
    }
}
