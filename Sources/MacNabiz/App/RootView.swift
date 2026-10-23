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
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                MiniStatusBar().environmentObject(monitor)
            }
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("MacNabız")
        .onChange(of: monitor.cpu) { _, _ in
            notify.evaluate(monitor)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .dashboard {
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

/// Kenar çubuğunun altındaki canlı mini gösterge.
struct MiniStatusBar: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 6) {
            Divider()
            HStack {
                miniStat("cpu", "\(Int(monitor.cpu.rounded()))%", Fmt.color(for: monitor.cpu))
                Spacer()
                miniStat("memorychip", "\(Int(monitor.memory.pressure.rounded()))%", Fmt.color(for: monitor.memory.pressure))
                Spacer()
                miniStat("internaldrive", "\(Int(monitor.disk.usedPercent.rounded()))%", Fmt.color(for: monitor.disk.usedPercent))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func miniStat(_ icon: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(color)
            Text(value).font(.caption).monospacedDigit()
        }
    }
}
