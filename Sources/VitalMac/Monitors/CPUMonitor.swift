import Foundation
import Darwin

/// Sistem geneli CPU kullanımını mach `host_statistics` tick sayaçlarıyla ölçer.
/// İki örnek arasındaki farktan yüzde hesaplar.
final class CPUMonitor {
    private var previous: host_cpu_load_info?

    struct Usage {
        var total: Double   // toplam kullanım %
        var user: Double    // kullanıcı + nice %
        var system: Double  // sistem %
    }

    func usage() -> Usage {
        guard let load = Self.hostCPULoad() else { return Usage(total: 0, user: 0, system: 0) }
        defer { previous = load }
        guard let prev = previous else { return Usage(total: 0, user: 0, system: 0) }

        // cpu_ticks: (USER, SYSTEM, IDLE, NICE)
        let user   = Double(load.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle   = Double(load.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice   = Double(load.cpu_ticks.3 &- prev.cpu_ticks.3)

        let total = user + system + idle + nice
        guard total > 0 else { return Usage(total: 0, user: 0, system: 0) }

        let used = (user + system + nice) / total * 100
        return Usage(
            total: used,
            user: (user + nice) / total * 100,
            system: system / total * 100
        )
    }

    private static func hostCPULoad() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }
}
