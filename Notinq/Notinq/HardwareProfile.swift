import Foundation
import Darwin

struct HardwareProfile: Codable, Equatable, Sendable {
    var architecture: String
    var cpuName: String
    var physicalMemoryBytes: UInt64
    var availableMemoryBytes: UInt64
    var isAppleSilicon: Bool
    var isIntel: Bool
    var recommendedModelIDs: [String]

    var totalMemoryGB: Int {
        Int(physicalMemoryBytes / 1_073_741_824)
    }

    var availableMemoryGB: Int {
        Int(availableMemoryBytes / 1_073_741_824)
    }

    var summary: String {
        "\(cpuName) · \(architecture) · \(totalMemoryGB) GB RAM"
    }
}

enum HardwareDetector {
    static func detect() -> HardwareProfile {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let availableMemory = availableMemoryBytes()
        let architecture = cpuArchitecture()
        let cpuName = processorName()
        let isAppleSilicon = architecture.contains("arm64")
        let isIntel = architecture.contains("x86_64")

        return HardwareProfile(
            architecture: architecture,
            cpuName: cpuName,
            physicalMemoryBytes: physicalMemory,
            availableMemoryBytes: availableMemory,
            isAppleSilicon: isAppleSilicon,
            isIntel: isIntel,
            recommendedModelIDs: recommendedModelIDs(for: physicalMemory)
        )
    }

    static func recommendedModelIDs(for physicalMemoryBytes: UInt64) -> [String] {
        let eightGB = UInt64(8) * 1_073_741_824
        let sixteenGB = UInt64(16) * 1_073_741_824
        let twentyFourGB = UInt64(24) * 1_073_741_824

        _ = eightGB
        _ = sixteenGB
        _ = twentyFourGB
        return ["qwen-3-4b", "qwen-2-5-3b"]
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

        guard result == KERN_SUCCESS else { return 0 }

        let pages = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.speculative_count)
        return pages * UInt64(pageSize)
    }

    private static func cpuArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
    }

    private static func processorName() -> String {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return cpuArchitecture() }

        var result = [CChar](repeating: 0, count: Int(size))
        let status = sysctlbyname("machdep.cpu.brand_string", &result, &size, nil, 0)
        guard status == 0 else { return cpuArchitecture() }
        return String(cString: result)
    }
}
