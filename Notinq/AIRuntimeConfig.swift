import Foundation

struct AIRuntimeConfig: Sendable {
    struct Llama: Sendable {
        var threads: Int32
        var contextSize: Int32
        var maxTokens: Int32
        var gpuLayers: Int32
        var temperature: Float
        var topP: Float
        var repeatPenalty: Float
    }

    var llama: Llama
    var idleUnloadSeconds: TimeInterval

    static var isDevMode: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var current: AIRuntimeConfig {
        let maxThreads = Int32(min(4, ProcessInfo.processInfo.activeProcessorCount))
        let isLowMemoryMachine = ProcessInfo.processInfo.physicalMemory <= (8 * 1024 * 1024 * 1024)
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let scaledGpuLayers: Int32 = {
            if physicalMemory <= (8 * 1024 * 1024 * 1024) {
                return 3
            }
            if physicalMemory <= (16 * 1024 * 1024 * 1024) {
                return 6
            }
            if physicalMemory <= (24 * 1024 * 1024 * 1024) {
                return 10
            }
            return 16
        }()

        if isLowPowerMode {
            return AIRuntimeConfig(
                llama: .init(
                    threads: min(2, maxThreads),
                    contextSize: 1024,
                    maxTokens: 256,
                    gpuLayers: min(2, scaledGpuLayers),
                    temperature: 0.6,
                    topP: 0.9,
                    repeatPenalty: 1.1
                ),
                idleUnloadSeconds: 120
            )
        }

        if isLowMemoryMachine {
            return AIRuntimeConfig(
                llama: .init(
                    threads: max(2, min(4, maxThreads)),
                    contextSize: 1024,
                    maxTokens: 256,
                    gpuLayers: min(4, scaledGpuLayers),
                    temperature: 0.6,
                    topP: 0.9,
                    repeatPenalty: 1.1
                ),
                idleUnloadSeconds: 120
            )
        }

        if isDevMode {
            return AIRuntimeConfig(
                llama: .init(
                    threads: maxThreads,
                    contextSize: 1024,
                    maxTokens: 256,
                    gpuLayers: 4,
                    temperature: 0.6,
                    topP: 0.9,
                    repeatPenalty: 1.1
                ),
                idleUnloadSeconds: 180
            )
        }

        return AIRuntimeConfig(
            llama: .init(
                threads: maxThreads,
                contextSize: 2048,
                maxTokens: 512,
                gpuLayers: min(8, scaledGpuLayers),
                temperature: 0.6,
                topP: 0.9,
                repeatPenalty: 1.1
            ),
            idleUnloadSeconds: 240
        )
    }
}

enum AIPerfLog {
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[AI]", message())
        #endif
    }
}
extension Notification.Name {
    static let notinqAIWillUseLlama = Notification.Name("notinq.ai.willUseLlama")
    static let notinqLocalModelDidChange = Notification.Name("notinq.ai.localModelDidChange")
}
