import Foundation
import Darwin

enum AICapabilityTier: String, Codable, CaseIterable, Sendable {
    case basic
    case standard
    case advanced

    var title: String {
        switch self {
        case .basic:
            return "Basic"
        case .standard:
            return "Standard"
        case .advanced:
            return "Advanced"
        }
    }
}

struct AICapabilitySnapshot: Codable, Equatable, Sendable {
    var physicalMemoryBytes: UInt64
    var availableMemoryBytes: UInt64
    var cpuArchitecture: String
    var tier: AICapabilityTier
}

enum AICapabilityDetector {
    static func capture() -> AICapabilitySnapshot {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let availableMemory = Self.availableMemoryBytes()
        let architecture = Self.cpuArchitecture()

        return AICapabilitySnapshot(
            physicalMemoryBytes: physicalMemory,
            availableMemoryBytes: availableMemory,
            cpuArchitecture: architecture,
            tier: Self.tier(for: physicalMemory)
        )
    }

    static func tier(for physicalMemoryBytes: UInt64) -> AICapabilityTier {
        let sixGB = UInt64(6) * 1024 * 1024 * 1024
        let twelveGB = UInt64(12) * 1024 * 1024 * 1024

        if physicalMemoryBytes < sixGB {
            return .basic
        } else if physicalMemoryBytes < twelveGB {
            return .standard
        } else {
            return .advanced
        }
    }

    private static func availableMemoryBytes() -> UInt64 {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        let pages = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.speculative_count)

        return pages * UInt64(pageSize)
    }

    private static func cpuArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)

        let machine = withUnsafePointer(to: &systemInfo.machine) { pointer -> String in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }

        if machine.contains("arm64") {
            return "arm64"
        }
        if machine.contains("x86_64") {
            return "x86_64"
        }
        return machine
    }
}

final class AICapabilityManager {
    static let shared = AICapabilityManager()

    private(set) var snapshot: AICapabilitySnapshot = AICapabilityDetector.capture()

    private init() {}

    var currentTier: AICapabilityTier {
        snapshot.tier
    }

    func refresh() {
        snapshot = AICapabilityDetector.capture()
        NotificationCenter.default.post(name: .notinqAICapabilityDidChange, object: nil)
    }
}

extension Notification.Name {
    static let notinqAICapabilityDidChange = Notification.Name("notinq.ai.capabilityDidChange")
}
