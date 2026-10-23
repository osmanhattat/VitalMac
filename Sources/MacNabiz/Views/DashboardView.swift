import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var monitor: SystemMonitor
    /// Ekran dışı görüntü alma için kaydırma alanı olmadan çizilebilir.
    var scrolls = true

    var body: some View {
        Group {
            if scrolls { ScrollView { content } } else { content }
        }
        .pageBackground()
        .navigationTitle("Panel")
    }

    private var content: some View {
            VStack(spacing: 16) {
                vitalsHero

                // Geçmiş grafikleri
                HStack(alignment: .top, spacing: 16) {
                    Card(title: "CPU Geçmişi", systemImage: "cpu", tint: Theme.cpu) {
                        Sparkline(data: monitor.cpuHistory, color: Theme.cpu)
                        HStack {
                            Text("Kullanıcı: \(Fmt.percent1(monitor.cpuUser))")
                            Spacer()
                            Text("Sistem: \(Fmt.percent1(monitor.cpuSystem))")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Card(title: "Bellek Geçmişi", systemImage: "memorychip", tint: Theme.memory) {
                        Sparkline(data: monitor.memHistory, color: Theme.memory)
                        HStack(spacing: 8) {
                            StatBadge(label: "Kablolu", value: Fmt.bytes(monitor.memory.wired))
                            StatBadge(label: "Sıkıştırılmış", value: Fmt.bytes(monitor.memory.compressed))
                            StatBadge(label: "Boş", value: Fmt.bytes(monitor.memory.free))
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                // Ağ + Enerji
                HStack(alignment: .top, spacing: 16) {
                    networkCard
                    energyCard
                }
                .fixedSize(horizontal: false, vertical: true)

                // Sıcaklık & Fan
                sensorsCard

                // En çok kaynak tüketen işlemler
                Card(title: "En çok CPU kullanan işlemler", systemImage: "flame", tint: Theme.heat) {
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

    /// Monitör başlığı: sağlık skoru + canlı nabız çizgisi + dört ana kanal.
    private var vitalsHero: some View {
        let score = monitor.healthScore
        let color: Color = score >= 75 ? Theme.ok : (score >= 50 ? Theme.warn : Theme.alert)
        let label = score >= 75 ? "Sistem sağlıklı" : (score >= 50 ? "Orta yük" : "Yüksek yük")
        let bpm = Pulse.bpm(forCPU: monitor.cpu)
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow("Sistem nabzı", color: Theme.pulse)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(score)")
                            .font(Theme.readout(58))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                        Text("/100").font(Theme.readout(18)).foregroundStyle(Theme.muted)
                    }
                    Label(label, systemImage: "circle.fill")
                        .labelStyle(StatusLabelStyle(color: color))
                }
                .frame(width: 190, alignment: .leading)

                VStack(alignment: .trailing, spacing: 6) {
                    PulseTrace(bpm: bpm, color: Theme.pulse)
                        .frame(height: 78)
                    HStack(spacing: 14) {
                        Eyebrow("\(Int(bpm.rounded())) atış/dk · CPU yüküne bağlı", size: 9)
                        if monitor.sensors.available && monitor.sensors.cpuTemp > 0 {
                            Eyebrow("SoC \(Int(monitor.sensors.cpuTemp.rounded()))°C",
                                    color: Fmt.color(for: monitor.sensors.cpuTemp), size: 9)
                        }
                    }
                }
            }
            .padding(20)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            HStack(spacing: 0) {
                VitalChannel(label: "İşlemci", value: monitor.cpu,
                             detail: "\(monitor.coreCount) çekirdek · kullanıcı \(Fmt.percent1(monitor.cpuUser))",
                             color: Theme.cpu, history: monitor.cpuHistory)
                channelDivider
                VitalChannel(label: "GPU", value: monitor.gpu.utilization,
                             detail: monitor.gpu.available ? "\(Fmt.bytes(monitor.gpu.inUseMemory)) kullanımda" : "ölçülemiyor",
                             color: Theme.gpu, history: monitor.gpuHistory)
                channelDivider
                VitalChannel(label: "Bellek", value: monitor.memory.pressure,
                             detail: "\(Fmt.bytes(monitor.memory.used)) / \(Fmt.bytes(monitor.memory.total))",
                             color: Theme.memory, history: monitor.memHistory)
                channelDivider
                VitalChannel(label: "Disk", value: monitor.disk.usedPercent,
                             detail: "\(Fmt.bytes(monitor.disk.free)) boş",
                             color: Theme.disk, history: [])
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .cardSurface(cornerRadius: 20)
        .animation(.easeOut(duration: 0.35), value: monitor.healthScore)
    }

    private var channelDivider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1).padding(.horizontal, 18)
    }

    @ViewBuilder
    private var sensorsCard: some View {
        Card(title: "Sıcaklık & Fan", systemImage: "thermometer.medium", tint: Theme.heat) {
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
                        StatBadge(label: "Fan \(index + 1)", value: "\(Int(rpm)) RPM", color: Theme.disk)
                    }
                    if monitor.sensors.fans.isEmpty {
                        StatBadge(label: "Fan", value: "yok/pasif")
                    }
                }
                Sparkline(data: monitor.tempHistory, color: Theme.heat)
                    .frame(height: 60)
            } else {
                Text("Sensör verisi okunamadı.").foregroundStyle(.secondary).font(.callout)
            }
        }
    }

    private var networkCard: some View {
        Card(title: "Ağ", systemImage: "network", tint: Theme.network) {
            HStack(spacing: 8) {
                StatBadge(label: "↓ İndirme", value: Fmt.rate(monitor.network.downBytesPerSec), color: Theme.network)
                StatBadge(label: "↑ Yükleme", value: Fmt.rate(monitor.network.upBytesPerSec), color: Theme.gpu)
            }
            AutoSparkline(data: monitor.netDownHistory, color: Theme.network)
            Text("Toplam: ↓ \(Fmt.bytes(monitor.network.totalDown))  ·  ↑ \(Fmt.bytes(monitor.network.totalUp))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var energyCard: some View {
        Card(title: "Enerji", systemImage: monitor.energy.isCharging ? "battery.100.bolt" : "battery.75", tint: Theme.ok) {
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
                        Text(batteryTimeText)
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

    private var batteryTimeText: String {
        let e = monitor.energy
        if e.onACPower && !e.isCharging { return e.percent >= 99 ? "Tam dolu" : "Şarj beklemede" }
        return Fmt.duration(minutes: e.timeRemaining) + (e.isCharging ? " içinde dolar" : " kaldı")
    }

    private func healthTR(_ s: String) -> String {
        switch s {
        case "Good": return "İyi"
        case "Fair": return "Orta"
        case "Poor": return "Zayıf"
        case "Check Battery": return "Kontrol gerekli"
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

/// Renkli nokta + metin durum etiketi.
private struct StatusLabelStyle: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(color)
            configuration.title.font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(color)
        }
    }
}
