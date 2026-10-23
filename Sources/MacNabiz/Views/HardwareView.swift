import SwiftUI

struct HardwareView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @StateObject private var bluetooth = BluetoothMonitor()
    private let hw = HardwareInfo.current

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Üst künye
                Card(title: "Genel Bakış", systemImage: "desktopcomputer") {
                    HStack(spacing: 16) {
                        Image(systemName: monitor.energy.hasBattery ? "laptopcomputer" : "desktopcomputer")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hw.chip).font(.title2.bold())
                            Text(monitor.energy.hasBattery ? "Dizüstü (pilli)" : "Masaüstü")
                                .foregroundStyle(.secondary)
                            Text("Model: \(hw.model)  ·  macOS \(shortOS)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                // İşlemci
                Card(title: "İşlemci (CPU)", systemImage: "cpu") {
                    InfoRow(label: "Çip", value: hw.chip)
                    InfoRow(label: "Çekirdek", value: "\(hw.physicalCores) fiziksel · \(hw.logicalCores) mantıksal")
                    if hw.performanceCores > 0 || hw.efficiencyCores > 0 {
                        InfoRow(label: "Yapı",
                                value: "\(hw.performanceCores) performans + \(hw.efficiencyCores) verimlilik")
                    }
                    Divider()
                    LiveBar(label: "Anlık kullanım", value: monitor.cpu, color: Fmt.color(for: monitor.cpu))
                }

                // Grafik işlemci
                Card(title: "Grafik İşlemci (GPU)", systemImage: "cpu.fill") {
                    InfoRow(label: "GPU", value: hw.gpuName)
                    if hw.gpuCores > 0 {
                        InfoRow(label: "Çekirdek", value: "\(hw.gpuCores) GPU çekirdeği")
                    }
                    InfoRow(label: hw.gpuUnified ? "GPU belleği (paylaşımlı)" : "VRAM",
                            value: Fmt.bytes(hw.gpuMemory))
                    if hw.gpuUnified {
                        Text("Apple Silicon birleşik bellek: GPU, sistem RAM'ini paylaşır.")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    if monitor.gpu.available {
                        LiveBar(label: "Anlık kullanım", value: monitor.gpu.utilization,
                                color: Fmt.color(for: monitor.gpu.utilization))
                        InfoRow(label: "Kullanımdaki GPU belleği", value: Fmt.bytes(monitor.gpu.inUseMemory))
                    } else {
                        Text("Anlık GPU kullanımı bu sistemde okunamıyor.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Bellek
                Card(title: "Bellek (RAM)", systemImage: "memorychip") {
                    InfoRow(label: "Toplam", value: Fmt.bytes(hw.ramTotal))
                    InfoRow(label: "Kullanılan", value: "\(Fmt.bytes(monitor.memory.used)) (\(Int(monitor.memory.pressure.rounded()))%)")
                    InfoRow(label: "Boş", value: Fmt.bytes(monitor.memory.free))
                    Divider()
                    LiveBar(label: "Bellek baskısı", value: monitor.memory.pressure,
                            color: Fmt.color(for: monitor.memory.pressure))
                }

                // Bluetooth çevre birimleri (pil bildirenler)
                if !bluetooth.devices.isEmpty {
                    Card(title: "Bluetooth Cihazları", systemImage: "wave.3.right") {
                        ForEach(bluetooth.devices) { device in
                            HStack {
                                Image(systemName: "battery.50").foregroundStyle(Fmt.color(for: Double(100 - device.battery)))
                                Text(device.name + (device.detail.isEmpty ? "" : " (\(device.detail))"))
                                Spacer()
                                Text("\(device.battery)%").monospacedDigit().fontWeight(.medium)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Donanım")
        .onAppear { bluetooth.scan() }
    }

    private var shortOS: String {
        hw.osVersion
            .replacingOccurrences(of: "Version ", with: "")
            .components(separatedBy: " (").first ?? hw.osVersion
    }
}

/// Etiket — değer satırı.
struct InfoRow: View {
    var label: String
    var value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

/// Etiket + canlı yüzde çubuğu.
struct LiveBar: View {
    var label: String
    var value: Double
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value.rounded()))%").fontWeight(.semibold).monospacedDigit()
            }
            .font(.callout)
            ProgressView(value: min(max(value / 100, 0), 1)).tint(color)
        }
    }
}
