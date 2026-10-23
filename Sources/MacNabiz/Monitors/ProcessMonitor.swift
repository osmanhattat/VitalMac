import Foundation
import Darwin
import AppKit

/// Tek bir işlemin anlık görüntüsü.
struct ProcInfo: Identifiable {
    let id: pid_t
    var pid: pid_t { id }
    var name: String
    var cpu: Double       // CPU yüzdesi (tek çekirdek bazlı, Activity Monitor gibi)
    var memory: UInt64    // yerleşik (resident) bellek, bayt
    var isApp: Bool       // kullanıcı uygulaması mı (dock'ta görünen)
    var bundleId: String?
    var icon: NSImage?
}

/// libproc ile işlem listesini ve her işlemin CPU/RAM kullanımını ölçer.
/// CPU yüzdesi iki örnek arasındaki CPU zaman farkından hesaplanır.
/// `snapshot()` yalnızca tek bir seri kuyrukta çağrıldığı için durum erişimi güvenlidir.
final class ProcessMonitor: @unchecked Sendable {
    private struct Sample { var cpuTimeNs: UInt64; var timestamp: TimeInterval }
    private var previous: [pid_t: Sample] = [:]

    func snapshot() -> [ProcInfo] {
        let now = Date().timeIntervalSince1970
        let pids = Self.allPIDs()

        // Dock uygulamalarını PID -> NSRunningApplication eşlemesiyle zenginleştir.
        var appByPid: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            appByPid[app.processIdentifier] = app
        }

        var result: [ProcInfo] = []
        var newPrev: [pid_t: Sample] = [:]
        result.reserveCapacity(pids.count)

        for pid in pids {
            guard let ti = Self.taskInfo(pid) else { continue }
            let cpuTime = ti.pti_total_user + ti.pti_total_system   // nanosaniye

            var cpuPercent = 0.0
            if let prev = previous[pid] {
                let dt = now - prev.timestamp
                if dt > 0 {
                    let deltaSec = Double(cpuTime &- prev.cpuTimeNs) / 1_000_000_000.0
                    cpuPercent = max(0, deltaSec / dt * 100)
                }
            }
            newPrev[pid] = Sample(cpuTimeNs: cpuTime, timestamp: now)

            let app = appByPid[pid]
            let name = app?.localizedName ?? Self.procName(pid) ?? "PID \(pid)"

            result.append(ProcInfo(
                id: pid,
                name: name,
                cpu: cpuPercent,
                memory: ti.pti_resident_size,
                isApp: app != nil,
                bundleId: app?.bundleIdentifier,
                icon: app?.icon
            ))
        }

        previous = newPrev
        return result
    }

    // MARK: - libproc sarmalayıcıları

    static func allPIDs() -> [pid_t] {
        let maxBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard maxBytes > 0 else { return [] }
        let capacity = Int(maxBytes) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, maxBytes)
        let n = Int(bytes) / MemoryLayout<pid_t>.stride
        return Array(pids.prefix(n)).filter { $0 > 0 }
    }

    static func taskInfo(_ pid: pid_t) -> proc_taskinfo? {
        var ti = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let r = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size)
        return r == size ? ti : nil
    }

    static func procName(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let r = proc_name(pid, &buf, UInt32(buf.count))
        return r > 0 ? String(cString: buf) : nil
    }

    static func path(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let r = proc_pidpath(pid, &buf, UInt32(buf.count))
        return r > 0 ? String(cString: buf) : nil
    }
}
