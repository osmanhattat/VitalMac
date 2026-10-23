import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                healthBanner

                // Dört ana halka göstergesi
                HStack(spacing: 16) {
                    RingGauge(
                        value: monitor.cpu,
                        label: "İşlemci",
                        color: Fmt.color(for: monitor.cpu),
                        subtitle: "\(monitor.coreCount) çekirdek"
                    )
                    RingGauge(
                        value: monitor.gpu.utilization,
                        label: "GPU",
                        color: Fmt.color(for: monitor.gpu.utilization),
                        subtitle: monitor.gpu.available
                            ? "\(Fmt.bytes(monitor.gpu.inUseMemory)) kullanımda"
                            : "kullanılamıyor"
                    )
                    RingGauge(
                        value: monitor.memory.pressure,
                        label: "Bellek",
                        color: Fmt.color(for: monitor.memory.pressure),
                        subtitle: "\(Fmt.bytes(monitor.memory.used)) / \(Fmt.bytes(monitor.memory.total))"
                    )
                    RingGauge(
                        value: monitor.disk.usedPercent,
                        label: "Disk",
                        color: Fmt.color(for: monitor.disk.usedPercent),
                        subtitle: "\(Fmt.bytes(monitor.disk.free)) boş"
                    )
                }

                // Geçmiş grafikleri
                HStack(spacing: 16) {
                    Card(title: "CPU Geçmişi", systemImage: "cpu", tint: .blue) {
                        Sparkline(data: monitor.cpuHistory, color: .blue)
                        HStack {
                            Text("Kullanıcı: \(Fmt.percent1(monitor.cpuUser))")
                            Spacer()
                            Text("Sistem: \(Fmt.percent1(monitor.cpuSystem))")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Card(title: "Bellek Geçmişi", systemImage: "memorychip", tint: .purple) {
                        Sparkline(data: monitor.memHistory, color: .purple)
                        HStack(spacing: 8) {
                            StatBadge(label: "Wired", value: Fmt.bytes(monitor.memory.wired))
                            StatBadge(label: "Sıkıştırılmış", value: Fmt.bytes(monitor.memory.compressed))
                            StatBadge(label: "Boş", value: Fmt.bytes(monitor.memory.free))
                        }
                    }
                }

                // Ağ + Enerji
                HStack(spacing: 16) {
                    networkCard
                    energyCard
                }

                // Sıcaklık & Fan
                sensorsCard

                // En çok kaynak tüketen işlemler
                Card(title: "En çok CPU kullanan işlemler", systemImage: "flame", tint: .orange) {
                    if monitor.processes.isEmpty {
                        Text("Ölçülüyor…").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(monitor.processes.prefix(7))) { proc in
                            HStack(spacing: 10) {
                                icon(for: proc)
                                Text(proc.name).lineLimit(1)
                                Spacer()
                                Text(Fmt.percent1(proc.cpu))
                                    .foregroundStyle(.secondary).monospacedDigit()
                                    .frame(width: 64, alignment: .trailing)
                                Text(Fmt.bytes(proc.memory))
                                    .foregroundStyle(.secondary).monospacedDigit()
                                    .frame(width: 84, alignment: .trailing)
                            }
                            .font(.callout)
                            if proc.id != monitor.processes.prefix(7).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Panel")
    }

    private var healthBanner: some View {
        let score = monitor.healthScore
        let color: Color = score >= 75 ? .green : (score >= 50 ? .orange : .red)
        let label = score >= 75 ? "Sistem sağlıklı" : (score >= 50 ? "Orta yük" : "Yüksek yük")
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 7)
                Circle().trim(from: 0, to: Double(score) / 100)
                    .stroke(
                        AngularGradient(gradient: Gradient(colors: [color.opacity(0.55), color]),
                                        center: .center),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.4), radius: 3)
                Text("\(score)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(.title3, design: .rounded).weight(.semibold))
                Text("CPU, bellek, disk ve sıcaklığa göre hesaplanan sağlık skoru.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if monitor.sensors.available && monitor.sensors.cpuTemp > 0 {
                StatBadge(label: "CPU sıcaklık", value: "\(Int(monitor.sensors.cpuTemp.rounded()))°C",
                          color: Fmt.color(for: monitor.sensors.cpuTemp))
                    .frame(width: 116)
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [color.opacity(0.16), color.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var sensorsCard: some View {
        Card(title: "Sıcaklık & Fan", systemImage: "thermometer.medium", tint: .red) {
            if monitor.sensors.available {
                HStack(spacing: 8) {
                    StatBadge(label: "CPU/SoC", value: "\(Int(monitor.sensors.cpuTemp.rounded()))°C",
                              color: Fmt.color(for: monitor.sensors.cpuTemp))
                    StatBadge(label: "En yüksek", value: "\(Int(monitor.sensors.maxTemp.rounded()))°C",
                              color: Fmt.color(for: monitor.sensors.maxTemp))
                    if monitor.sensors.batteryTemp > 0 {
                        StatBadge(label: "Pil", value: "\(Int(monitor.sensors.batteryTemp.rounded()))°C")
                    }
                    ForEach(Array(monitor.sensors.fans.enumerated()), id: \.offset) { index, rpm in
                        StatBadge(label: "Fan \(index + 1)", value: "\(Int(rpm)) RPM", color: .blue)
                    }
                    if monitor.sensors.fans.isEmpty {
                        StatBadge(label: "Fan", value: "yok/pasif")
                    }
                }
                Sparkline(data: monitor.tempHistory, color: .red)
                    .frame(height: 60)
            } else {
                Text("Sensör verisi okunamadı.").foregroundStyle(.secondary).font(.callout)
            }
        }
    }

    private var networkCard: some View {
        Card(title: "Ağ", systemImage: "network", tint: .teal) {
            HStack(spacing: 8) {
                StatBadge(label: "↓ İndirme", value: Fmt.rate(monitor.network.downBytesPerSec), color: .green)
                StatBadge(label: "↑ Yükleme", value: Fmt.rate(monitor.network.upBytesPerSec), color: .orange)
            }
            AutoSparkline(data: monitor.netDownHistory, color: .green)
            Text("Toplam: ↓ \(Fmt.bytes(monitor.network.totalDown))  ·  ↑ \(Fmt.bytes(monitor.network.totalUp))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var energyCard: some View {
        Card(title: "Enerji", systemImage: monitor.energy.isCharging ? "battery.100.bolt" : "battery.75", tint: .green) {
            if monitor.energy.hasBattery {
                HStack(spacing: 12) {
                    Text("\(Int(monitor.energy.percent.rounded()))%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Fmt.color(for: 100 - monitor.energy.percent))
                    VStack(alignment: .leading, spacing: 3) {
                        Label(monitor.energy.isCharging ? "Şarj oluyor"
                              : (monitor.energy.onACPower ? "Fişte (AC)" : "Pilde"),
                              systemImage: monitor.energy.isCharging ? "bolt.fill" : "powerplug")
                            .font(.callout)
                        Text(Fmt.duration(minutes: monitor.energy.timeRemaining) +
                             (monitor.energy.isCharging ? " (dolması)" : " (kalan)"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    StatBadge(label: "Sağlık", value: monitor.energy.health.isEmpty ? "—" : healthTR(monitor.energy.health))
                    StatBadge(label: "Çevrim", value: "\(monitor.energy.cycleCount)")
                }
            } else {
                HStack {
                    Image(systemName: "powerplug.fill").font(.title).foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Sürekli güç").font(.headline)
                        Text("Bu Mac'te pil yok (masaüstü).").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func healthTR(_ s: String) -> String {
        switch s {
        case "Good": return "İyi"
        case "Fair": return "Orta"
        case "Poor": return "Zayıf"
        default: return s
        }
    }

    @ViewBuilder
    private func icon(for proc: ProcInfo) -> some View {
        if let img = proc.icon {
            Image(nsImage: img).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: "gearshape.2")
                .foregroundStyle(.secondary).frame(width: 18)
        }
    }
}
