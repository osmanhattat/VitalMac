import Foundation

struct NetworkStats {
    var downBytesPerSec: Double
    var upBytesPerSec: Double
    var totalDown: UInt64
    var totalUp: UInt64

    static let zero = NetworkStats(downBytesPerSec: 0, upBytesPerSec: 0, totalDown: 0, totalUp: 0)
}

/// Tüm ağ arayüzlerinin (loopback hariç) toplam trafiğini `getifaddrs` ile okur,
/// iki örnek arasındaki farktan saniyelik hızı hesaplar.
final class NetworkMonitor {
    private var prevDown: UInt64 = 0
    private var prevUp: UInt64 = 0
    private var prevTime: TimeInterval = 0

    func stats() -> NetworkStats {
        let (down, up) = Self.counters()
        let now = Date().timeIntervalSince1970
        defer { prevDown = down; prevUp = up; prevTime = now }

        guard prevTime > 0 else {
            return NetworkStats(downBytesPerSec: 0, upBytesPerSec: 0, totalDown: down, totalUp: up)
        }
        let dt = now - prevTime
        guard dt > 0 else {
            return NetworkStats(downBytesPerSec: 0, upBytesPerSec: 0, totalDown: down, totalUp: up)
        }
        // 32-bit sayaç sarması olursa negatif farkı 0 say.
        let dDown = down >= prevDown ? Double(down - prevDown) : 0
        let dUp   = up   >= prevUp   ? Double(up - prevUp)     : 0
        return NetworkStats(
            downBytesPerSec: dDown / dt,
            upBytesPerSec: dUp / dt,
            totalDown: down,
            totalUp: up
        )
    }

    private static func counters() -> (down: UInt64, up: UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var ibytes: UInt64 = 0
        var obytes: UInt64 = 0
        var ptr = ifaddr
        while let p = ptr {
            let flags = Int32(p.pointee.ifa_flags)
            if let addr = p.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               (flags & IFF_LOOPBACK) == 0,
               let data = p.pointee.ifa_data {
                let nd = data.assumingMemoryBound(to: if_data.self)
                ibytes += UInt64(nd.pointee.ifi_ibytes)
                obytes += UInt64(nd.pointee.ifi_obytes)
            }
            ptr = p.pointee.ifa_next
        }
        return (ibytes, obytes)
    }
}
