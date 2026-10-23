import SwiftUI
import AppKit

/// Menü çubuğu açılır penceresi: canlı özet + hızlı eylemler.
struct MenuBarView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg").foregroundStyle(.pink)
                Text("VitalMac").font(.headline)
                Spacer()
                Text("Skor \(monitor.healthScore)")
                    .font(.caption.bold()).monospacedDigit()
                    .foregroundStyle(monitor.healthScore >= 75 ? .green : (monitor.healthScore >= 50 ? .orange : .red))
            }

            Sparkline(data: monitor.cpuHistory, color: .blue).frame(height: 44)

            row("cpu", String(localized: "İşlemci"), monitor.cpu, String(localized: "\(monitor.coreCount) çekirdek"))
            if monitor.gpu.available {
                row("cpu.fill", "GPU", monitor.gpu.utilization,
                    String(localized: "\(Fmt.bytes(monitor.gpu.inUseMemory)) kullanımda"))
            }
            row("memorychip", "Bellek", monitor.memory.pressure,
                String(localized: "\(Fmt.bytes(monitor.memory.used)) / \(Fmt.bytes(monitor.memory.total))"))
            row("internaldrive", String(localized: "Disk"), monitor.disk.usedPercent,
                String(localized: "\(Fmt.bytes(monitor.disk.free)) boş"))

            Divider()

            HStack {
                Label(Fmt.rate(monitor.network.downBytesPerSec), systemImage: "arrow.down")
                    .foregroundStyle(.green)
                Spacer()
                Label(Fmt.rate(monitor.network.upBytesPerSec), systemImage: "arrow.up")
                    .foregroundStyle(.orange)
            }
            .font(.caption).monospacedDigit()

            if monitor.energy.hasBattery {
                HStack {
                    Label("Pil \(Int(monitor.energy.percent.rounded()))%",
                          systemImage: monitor.energy.isCharging ? "battery.100.bolt" : "battery.75")
                    Spacer()
                    Text(monitor.energy.isCharging ? String(localized: "şarjda") : Fmt.duration(minutes: monitor.energy.timeRemaining))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            if monitor.sensors.available && monitor.sensors.cpuTemp > 0 {
                HStack {
                    Label("\(Int(monitor.sensors.cpuTemp.rounded()))°C", systemImage: "thermometer.medium")
                        .foregroundStyle(Fmt.color(for: monitor.sensors.cpuTemp))
                    Spacer()
                    if !monitor.sensors.fans.isEmpty {
                        let avg = monitor.sensors.fans.reduce(0, +) / Double(monitor.sensors.fans.count)
                        Label("\(Int(avg)) RPM", systemImage: "fan").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }

            Divider()

            Text("En çok CPU").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(monitor.processes.prefix(3))) { proc in
                HStack {
                    Text(proc.name).lineLimit(1).font(.callout)
                    Spacer()
                    Text(Fmt.percent1(proc.cpu)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Button("Pencereyi Aç") {
                    NSApp.activate(ignoringOtherApps: true)
                    let mainWindows = NSApp.windows.filter { $0.canBecomeMain && $0.isVisible }
                    if mainWindows.isEmpty {
                        // Pencere kapatılmışsa yeniden oluştur.
                        openWindow(id: VitalMacApp.mainWindowID)
                    } else {
                        mainWindows.forEach { $0.makeKeyAndOrderFront(nil) }
                    }
                }
                Spacer()
                Button("Çık") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 280)
    }

    private func row(_ icon: String, _ label: String, _ value: Double, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Fmt.color(for: value))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(label).font(.callout)
                    Spacer()
                    Text("\(Int(value.rounded()))%").font(.callout.bold()).monospacedDigit()
                }
                ProgressView(value: min(max(value / 100, 0), 1))
                    .tint(Fmt.color(for: value))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Menü çubuğunda görünen canlı etiket: mini CPU grafiği + yüzde.
struct MenuBarLabel: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        HStack(spacing: 3) {
            Canvas { context, size in
                let data = monitor.cpuHistory
                guard data.count > 1 else { return }
                var path = Path()
                let stepX = size.width / CGFloat(data.count - 1)
                for (index, value) in data.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = size.height - CGFloat(min(max(value, 0), 100) / 100) * size.height
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .foreground, lineWidth: 1.4)
            }
            .frame(width: 26, height: 14)

            Text("\(Int(monitor.cpu.rounded()))%")
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
        }
    }
}
