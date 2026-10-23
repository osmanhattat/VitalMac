import SwiftUI

struct BoostView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @ObservedObject var booster: Booster

    @State private var purgeMemory = true
    @State private var selectedPids = Set<pid_t>()
    @State private var bgApps: [BackgroundApp] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                bigButton

                Card(title: "Bellek Temizleme", systemImage: "memorychip") {
                    Toggle(isOn: $purgeMemory) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("İnaktif belleği boşalt (purge)")
                            Text("Yönetici şifresi istenir. Şu an kullanılan: \(Fmt.bytes(monitor.memory.used)) / \(Fmt.bytes(monitor.memory.total))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Card(
                    title: "Kapatılabilir arka plan uygulamaları",
                    systemImage: "rectangle.stack.badge.minus"
                ) {
                    if bgApps.isEmpty {
                        Text("Arka planda kapatılabilecek uygulama bulunamadı.")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(bgApps) { app in
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(
                                    get: { selectedPids.contains(app.id) },
                                    set: { on in
                                        if on { selectedPids.insert(app.id) }
                                        else { selectedPids.remove(app.id) }
                                    }
                                ))
                                .labelsHidden()
                                if let icon = app.icon {
                                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                                }
                                Text(app.name).lineLimit(1)
                                Spacer()
                                Text(Fmt.bytes(app.memory))
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                            .font(.callout)
                        }
                        HStack {
                            Button("Tümünü Seç") { selectedPids = Set(bgApps.map { $0.id }) }
                            Button("Seçimi Temizle") { selectedPids.removeAll() }
                        }
                        .buttonStyle(.link).font(.caption)
                    }
                }

                if !booster.log.isEmpty {
                    Card(title: "Günlük", systemImage: "text.alignleft") {
                        ForEach(booster.log.prefix(8), id: \.self) { line in
                            Text(line).font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Hızlandır")
        .onAppear(perform: refreshApps)
    }

    private var bigButton: some View {
        Button(action: runBoost) {
            VStack(spacing: 8) {
                if booster.isWorking {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Image(systemName: "bolt.fill").font(.system(size: 40))
                }
                Text(booster.isWorking ? "Çalışıyor…" : "HIZLANDIR")
                    .font(.title2.bold())
                Text(summary).font(.caption).opacity(0.9)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .opacity(booster.isWorking ? 0.85 : 1)
            .background(
                LinearGradient(colors: [.orange, .pink],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20)
            )
        }
        .buttonStyle(.plain)
        .disabled(booster.isWorking)
    }

    private var summary: String {
        var parts: [String] = []
        if !selectedPids.isEmpty { parts.append(String(localized: "\(selectedPids.count) uygulama kapatılacak")) }
        if purgeMemory { parts.append(String(localized: "bellek temizlenecek")) }
        return parts.isEmpty ? String(localized: "Yapılacakları aşağıdan seçin") : parts.joined(separator: " · ")
    }

    private func refreshApps() {
        let memByPid = Dictionary(monitor.processes.map { ($0.pid, $0.memory) }) { a, _ in a }
        bgApps = booster.backgroundApps { memByPid[$0] ?? 0 }
    }

    private func runBoost() {
        let toQuit = bgApps.filter { selectedPids.contains($0.id) }.map { ($0.id, $0.name) }
        booster.boost(quitPids: toQuit, purge: purgeMemory)
        selectedPids.removeAll()
        // Listeyi kısa süre sonra tazele.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: refreshApps)
    }
}
