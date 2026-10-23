import Foundation
import Metal
import IOKit

/// Donanım künyesi (bir kez okunur, değişmez).
struct HardwareInfo {
    var chip: String           // "Apple M5 Pro"
    var model: String          // "Mac17,9"
    var physicalCores: Int
    var performanceCores: Int
    var efficiencyCores: Int
    var logicalCores: Int
    var ramTotal: UInt64
    var gpuName: String
    var gpuCores: Int          // 0 = bilinmiyor
    var gpuMemory: UInt64      // önerilen azami çalışma kümesi (GPU bütçesi)
    var gpuUnified: Bool       // paylaşımlı bellek (Apple Silicon)
    var osVersion: String

    static let current = HardwareInfo.gather()

    private static func gather() -> HardwareInfo {
        var gpuName = "Bilinmeyen GPU"
        var gpuMem: UInt64 = 0
        var unified = false
        if let device = MTLCreateSystemDefaultDevice() {
            gpuName = device.name
            gpuMem = device.recommendedMaxWorkingSetSize
            unified = device.hasUnifiedMemory
        }

        return HardwareInfo(
            chip: sysctlString("machdep.cpu.brand_string") ?? "Bilinmeyen işlemci",
            model: sysctlString("hw.model") ?? "?",
            physicalCores: Int(sysctlInt("hw.physicalcpu") ?? 0),
            performanceCores: Int(sysctlInt("hw.perflevel0.physicalcpu") ?? 0),
            efficiencyCores: Int(sysctlInt("hw.perflevel1.physicalcpu") ?? 0),
            logicalCores: Int(sysctlInt("hw.logicalcpu") ?? 0),
            ramTotal: UInt64(sysctlInt("hw.memsize") ?? 0),
            gpuName: gpuName,
            gpuCores: gpuCoreCount(),
            gpuMemory: gpuMem,
            gpuUnified: unified,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    // MARK: - Düşük seviye okuyucular

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    /// GPU çekirdek sayısını IORegistry "gpu-core-count" özelliğinden okur.
    private static func gpuCoreCount() -> Int {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator
        ) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var result = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let prop = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, "gpu-core-count" as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            )
            if let count = prop as? Int { result = count }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }
}
