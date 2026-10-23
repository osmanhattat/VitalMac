import Foundation

struct BTDevice: Identifiable {
    let id = UUID()
    var name: String
    var battery: Int   // 0–100
    var detail: String // "Sol/Sağ/Kutu" gibi
}

/// Bağlı Bluetooth cihazlarının pil seviyelerini `system_profiler` çıktısından
/// en iyi çabayla (best-effort) okur. Pil bildirmeyen cihazlar atlanır.
@MainActor
final class BluetoothMonitor: ObservableObject {
    @Published var devices: [BTDevice] = []
    @Published var scanning = false

    private let sectionHeaders: Set<String> = [
        "bluetooth", "connected", "not connected", "controller", "services", "devices"
    ]

    func scan() {
        scanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let (_, output) = Privileged.runShell("/usr/sbin/system_profiler", ["SPBluetoothDataType"])
            let parsed = self.parse(output)
            DispatchQueue.main.async {
                self.devices = parsed
                self.scanning = false
            }
        }
    }

    nonisolated private func parse(_ text: String) -> [BTDevice] {
        var result: [BTDevice] = []
        var currentDevice = ""
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // "Battery Level: 80%" gibi satır
            if line.lowercased().contains("battery"), let pct = percent(in: line) {
                let label = line.components(separatedBy: ":").first ?? "Pil"
                let detail = label.replacingOccurrences(of: "Battery Level", with: "")
                    .trimmingCharacters(in: .whitespaces)
                result.append(BTDevice(
                    name: currentDevice.isEmpty ? String(localized: "Bilinmeyen cihaz") : currentDevice,
                    battery: pct,
                    detail: detail
                ))
            } else if line.hasSuffix(":"), !line.contains(" ") || isDeviceHeader(line) {
                // Cihaz adı başlığı (örn. "AirPods Pro:")
                let name = String(line.dropLast())
                if !sectionHeaders.contains(name.lowercased()) {
                    currentDevice = name
                }
            }
        }
        // Aynı cihaz birden çok pil satırı verebilir; en yükseği yeterli özet.
        return result
    }

    nonisolated private func isDeviceHeader(_ line: String) -> Bool {
        // "Magic Mouse:" gibi boşluklu ama değer içermeyen başlıklar
        line.hasSuffix(":") && !line.contains(": ")
    }

    nonisolated private func percent(in line: String) -> Int? {
        guard let range = line.range(of: #"(\d{1,3})%"#, options: .regularExpression) else { return nil }
        let digits = line[range].dropLast()
        return Int(digits)
    }
}
