import Foundation
import SwiftUI

/// Ortak biçimlendirme yardımcıları (bayt, yüzde, renk eşikleri).
enum Fmt {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]
        return f
    }()

    /// Baytı insan okunur metne çevirir (örn. "1,2 GB").
    static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    static func bytes(_ value: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(clamping: value))
    }

    static func percent(_ v: Double) -> String { String(format: "%%%.0f", v) }
    static func percent1(_ v: Double) -> String { String(format: "%.1f%%", v) }

    /// Saniyelik hız (örn. "1,2 MB/sn").
    static func rate(_ bytesPerSec: Double) -> String {
        bytes(Int64(max(0, bytesPerSec))) + "/sn"
    }

    /// Dakikayı "2sa 15dk" biçimine çevirir (-1 = hesaplanıyor).
    static func duration(minutes: Int) -> String {
        guard minutes >= 0 else { return "hesaplanıyor…" }
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)sa \(m)dk" : "\(m)dk"
    }

    /// 0–100 yüzdesine göre durum rengi (yeşil → sarı → kırmızı).
    static func color(for percent: Double) -> Color {
        switch percent {
        case ..<60:  return .green
        case ..<85:  return .orange
        default:     return .red
        }
    }
}
