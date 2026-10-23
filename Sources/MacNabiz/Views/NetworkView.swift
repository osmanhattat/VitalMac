import SwiftUI

struct NetworkView: View {
    @EnvironmentObject var monitor: SystemMonitor

    @State private var apps: [AppNetUsage] = []
    @State private var sortOrder = [KeyPathComparator(\AppNetUsage.downRate, order: .reverse)]
    @State private var appMon = AppNetworkMonitor()
    @State private var queue = DispatchQueue(label: "com.hattat.macnabiz.appnet")
    @State private var timer: Timer?
    @State private var inFlight = false      // nettop ~1 sn sürer; örnekler üst üste binmesin
    @State private var loadedOnce = false

    private var sorted: [AppNetUsage] { apps.sorted(using: sortOrder) }

    var body: some View {
        VStack(spacing: 0) {
            // Üst özet
            HStack(spacing: 16) {
                StatBadge(label: "↓ İndirme", value: Fmt.rate(monitor.network.downBytesPerSec), color: .green)
                StatBadge(label: "↑ Yükleme", value: Fmt.rate(monitor.network.upBytesPerSec), color: .orange)
                StatBadge(label: "Toplam ↓", value: Fmt.bytes(monitor.network.totalDown))
                StatBadge(label: "Toplam ↑", value: Fmt.bytes(monitor.network.totalUp))
            }
            .padding(12)

            AutoSparkline(data: monitor.netDownHistory, color: .green)
                .frame(height: 50)
                .padding(.horizontal, 12)

            Divider().padding(.top, 8)

            if apps.isEmpty && !loadedOnce {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Uygulama-bazlı ağ kullanımı ölçülüyor… (nettop)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("Ağ kullanan uygulama bulunamadı ya da nettop okunamadı.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(sorted, sortOrder: $sortOrder) {
                    TableColumn("Uygulama") { app in
                        Text(app.name).lineLimit(1)
                    }
                    TableColumn("↓ İndirme", value: \.downRate) { app in
                        Text(Fmt.rate(app.downRate)).monospacedDigit()
                            .foregroundStyle(app.downRate > 0 ? .green : .secondary)
                    }
                    .width(120)
                    TableColumn("↑ Yükleme", value: \.upRate) { app in
                        Text(Fmt.rate(app.upRate)).monospacedDigit()
                            .foregroundStyle(app.upRate > 0 ? .orange : .secondary)
                    }
                    .width(120)
                    TableColumn("PID", value: \.pid) { app in
                        Text(app.pid > 0 ? "\(app.pid)" : "—").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(70)
                }
                .tableStyle(.inset)
            }
        }
        .navigationTitle("Ağ")
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private func start() {
        guard timer == nil else { return }   // onAppear birden fazla tetiklenirse ikinci zamanlayıcı kurma
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        guard !inFlight else { return }
        inFlight = true
        let mon = appMon
        queue.async {
            let result = mon.sample()
            DispatchQueue.main.async {
                apps = result
                inFlight = false
                loadedOnce = true
            }
        }
    }
}
