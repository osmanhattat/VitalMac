import SwiftUI

/// Kenar çubuğu bölümleri.
enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard  = "Panel"
    case hardware   = "Donanım"
    case processes  = "İşlemler"
    case disk       = "Disk Analizi"
    case network    = "Ağ"
    case boost      = "Hızlandır"
    case cleaner    = "Temizlik"
    case spaceSaver = "Alan Kazan"
    case uninstaller = "Uygulamalar"
    case startup    = "Başlangıç"
    case settings   = "Ayarlar"

    var id: String { rawValue }

    /// Görünen ad (etkin dile çevrilir; ham değer Türkçe anahtardır).
    var title: LocalizedStringKey { LocalizedStringKey(rawValue) }

    /// Kenar çubuğu grupları (sıra = görünüm sırası).
    static let groups: [(title: String, items: [SidebarItem])] = [
        (String(localized: "İzleme"), [.dashboard, .hardware, .processes, .network]),
        (String(localized: "Depolama"), [.disk, .spaceSaver, .cleaner]),
        (String(localized: "Bakım"), [.boost, .uninstaller, .startup]),
        (String(localized: "Uygulama"), [.settings]),
    ]

    var icon: String {
        switch self {
        case .dashboard:   return "gauge.with.dots.needle.67percent"
        case .hardware:    return "cpu"
        case .processes:   return "list.bullet.rectangle.portrait"
        case .disk:        return "internaldrive"
        case .network:     return "network"
        case .boost:       return "bolt.fill"
        case .cleaner:     return "sparkles"
        case .spaceSaver:  return "externaldrive.badge.minus"
        case .uninstaller: return "trash.square"
        case .startup:     return "power"
        case .settings:    return "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var notify: NotificationManager
    @State private var selection: SidebarItem? = .dashboard

    // Servisler tek örnek olarak burada yaşar.
    @StateObject private var booster = Booster()
    @StateObject private var cleaner = CacheCleaner()
    @StateObject private var uninstaller = AppUninstaller()
    @StateObject private var loginItems = LoginItemsService()
    @StateObject private var diskStore = DiskScanStore()
    @StateObject private var spaceSaver = SpaceSaverStore()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.groups, id: \.title) { group in
                    Section {
                        ForEach(group.items) { item in
                            Label(item.title, systemImage: item.icon).tag(item)
                        }
                    } header: {
                        Eyebrow(LocalizedStringKey(group.title), size: 9.5)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .listStyle(.sidebar)
            .tint(Theme.pulse)
            .safeAreaInset(edge: .top) { SidebarBrand() }
            .safeAreaInset(edge: .bottom) {
                MiniStatusBar().environmentObject(monitor)
            }
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .pageBackground()
        }
        .navigationTitle("VitalMac")
        #if DEBUG
        .task {
            await SnapshotRunner.run(select: { selection = $0 }, render: { item in
                AnyView((item == .dashboard ? AnyView(DashboardView(scrolls: false)) : AnyView(page(item)))
                    .environmentObject(monitor).environmentObject(notify))
            }, sidebar: AnyView(
                SnapshotSidebar().frame(width: 230, height: 1500)
                    .environmentObject(monitor)
            ))
        }
        #endif
        .onChange(of: monitor.cpu) { _, _ in
            notify.evaluate(monitor)
        }
    }

    private var detailView: some View { page(selection ?? .dashboard) }

    @ViewBuilder
    private func page(_ item: SidebarItem) -> some View {
        switch item {
        case .dashboard:   DashboardView()
        case .hardware:    HardwareView()
        case .processes:   ProcessesView(booster: booster)
        case .disk:        DiskView(store: diskStore)
        case .network:     NetworkView()
        case .boost:       BoostView(booster: booster)
        case .cleaner:     CleanerView(cleaner: cleaner)
        case .spaceSaver:  SpaceSaverView(store: spaceSaver)
        case .uninstaller: UninstallerView(uninstaller: uninstaller)
        case .startup:     StartupView(loginItems: loginItems)
        case .settings:    SettingsView()
        }
    }
}

/// Kenar çubuğunun üstündeki marka: işaret + ad + CPU'ya bağlı canlı mini nabız.
struct SidebarBrand: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Theme.pulse, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text("VitalMac").font(.system(.headline, design: .rounded))
                    Eyebrow("\(Int(Pulse.bpm(forCPU: monitor.cpu).rounded())) atış/dk", size: 8.5)
                }
                Spacer()
            }
            PulseTrace(bpm: Pulse.bpm(forCPU: monitor.cpu), color: Theme.pulse, lineWidth: 1.3, fps: 12)
                .frame(height: 22)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// Kenar çubuğunun altındaki canlı mini gösterge.
struct MiniStatusBar: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 8) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 0) {
                miniStat("CPU", monitor.cpu, Theme.cpu)
                miniStat("RAM", monitor.memory.pressure, Theme.memory)
                miniStat("DİSK", monitor.disk.usedPercent, Theme.disk)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private func miniStat(_ label: LocalizedStringKey, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Eyebrow(label, size: 8.5)
            Text("\(Int(value.rounded()))%")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(value >= 85 ? Theme.alert : Theme.ink)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inset)
                    Capsule().fill(color).frame(width: max(2, geo.size.width * min(max(value / 100, 0), 1)))
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
