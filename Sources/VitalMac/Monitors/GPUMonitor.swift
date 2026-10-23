import Foundation
import IOKit

struct GPUStats {
    var utilization: Double   // 0–100
    var inUseMemory: UInt64   // kullanılan GPU belleği (bayt)
    var available: Bool

    static let zero = GPUStats(utilization: 0, inUseMemory: 0, available: false)
}

/// GPU kullanımını IORegistry'deki IOAccelerator "PerformanceStatistics"
/// sözlüğünden okur (sudo gerektirmez). Birden çok GPU varsa en yükseğini raporlar.
final class GPUMonitor: Sendable {
    func stats() -> GPUStats {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return .zero
        }
        defer { IOObjectRelease(iterator) }

        var best = GPUStats.zero
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let perf = dict["PerformanceStatistics"] as? [String: Any] {
                let util = (perf["Device Utilization %"] as? NSNumber)?.doubleValue ?? 0
                let mem  = (perf["In use system memory"] as? NSNumber)?.uint64Value ?? 0
                best = GPUStats(
                    utilization: max(best.utilization, util),
                    inUseMemory: max(best.inUseMemory, mem),
                    available: true
                )
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return best
    }
}
