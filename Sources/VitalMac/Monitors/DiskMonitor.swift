import Foundation

struct DiskStats {
    var total: Int64
    var free: Int64
    var used: Int64
    var usedPercent: Double

    static let zero = DiskStats(total: 0, free: 0, used: 0, usedPercent: 0)
}

/// Disk birimi doluluk durumunu URL kaynak değerleriyle okur.
final class DiskMonitor {
    func stats(path: String = "/") -> DiskStats {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else {
            return .zero
        }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free  = values.volumeAvailableCapacityForImportantUsage ?? 0
        let used  = max(0, total - free)
        let pct   = total > 0 ? Double(used) / Double(total) * 100 : 0
        return DiskStats(total: total, free: free, used: used, usedPercent: pct)
    }
}
