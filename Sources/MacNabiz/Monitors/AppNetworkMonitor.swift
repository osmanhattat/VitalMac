import Foundation

struct AppNetUsage: Identifiable {
    let id: String      // "ad.pid"
    var name: String
    var pid: Int
    var downRate: Double // bayt/sn
    var upRate: Double
    var totalDown: UInt64
    var totalUp: UInt64
}

/// `nettop` çıktısını ayrıştırarak uygulama-bazlı ağ kullanımını hesaplar (sudo gerekmez).
final class AppNetworkMonitor {
    private struct Sample { var inBytes: UInt64; var outBytes: UInt64 }
    private var previous: [String: Sample] = [:]
    private var previousTime: TimeInterval = 0

    func sample() -> [AppNetUsage] {
        let (status, output) = Privileged.runShell(
            "/usr/bin/nettop", ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"]
        )
        guard status == 0, !output.isEmpty else {
            NSLog("MacNabız: nettop başarısız (kod %d): %@", status, String(output.prefix(300)))
            return []
        }

        let now = Date().timeIntervalSince1970
        let dt = previousTime > 0 ? now - previousTime : 1
        var result: [AppNetUsage] = []
        var newPrev: [String: Sample] = [:]

        for line in output.split(separator: "\n") {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let id = String(cols[0]).trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty,
                  let inBytes = UInt64(cols[1].trimmingCharacters(in: .whitespaces)),
                  let outBytes = UInt64(cols[2].trimmingCharacters(in: .whitespaces))
            else { continue }   // başlık satırı vb. atlanır

            newPrev[id] = Sample(inBytes: inBytes, outBytes: outBytes)
            var down = 0.0, up = 0.0
            if let p = previous[id], dt > 0 {
                down = inBytes >= p.inBytes ? Double(inBytes - p.inBytes) / dt : 0
                up   = outBytes >= p.outBytes ? Double(outBytes - p.outBytes) / dt : 0
            }

            let parts = id.split(separator: ".")
            let pid = Int(parts.last ?? "") ?? 0
            let name = parts.count > 1 ? parts.dropLast().joined(separator: ".") : id

            result.append(AppNetUsage(
                id: id, name: name, pid: pid,
                downRate: down, upRate: up, totalDown: inBytes, totalUp: outBytes
            ))
        }

        previous = newPrev
        previousTime = now
        return result.sorted { ($0.downRate + $0.upRate) > ($1.downRate + $1.upRate) }
    }
}
