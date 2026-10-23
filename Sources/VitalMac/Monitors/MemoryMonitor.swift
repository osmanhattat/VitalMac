import Foundation
import Darwin

struct MemoryStats {
    var total: UInt64       // toplam fiziksel RAM
    var used: UInt64        // kullanılan (aktif + wired + sıkıştırılmış)
    var app: UInt64         // uygulama belleği (aktif + inaktif, kabaca)
    var wired: UInt64       // çekirdek tarafından sabitlenen
    var compressed: UInt64  // sıkıştırılmış
    var free: UInt64        // boş
    var pressure: Double    // kullanım yüzdesi (0–100)

    static let zero = MemoryStats(total: 0, used: 0, app: 0, wired: 0,
                                  compressed: 0, free: 0, pressure: 0)
}

/// mach `host_statistics64` (HOST_VM_INFO64) ile RAM kullanımını ölçer.
final class MemoryMonitor {
    let total = ProcessInfo.processInfo.physicalMemory

    private let pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return UInt64(size)
    }()

    func stats() -> MemoryStats {
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &vmStats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            var z = MemoryStats.zero
            z.total = total
            z.free = total
            return z
        }

        let active     = UInt64(vmStats.active_count) * pageSize
        let inactive   = UInt64(vmStats.inactive_count) * pageSize
        let wired      = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let free       = UInt64(vmStats.free_count) * pageSize

        let used = active + wired + compressed
        let app  = active + inactive
        let pressure = total > 0 ? Double(used) / Double(total) * 100 : 0

        return MemoryStats(total: total, used: used, app: app, wired: wired,
                           compressed: compressed, free: free, pressure: pressure)
    }
}
