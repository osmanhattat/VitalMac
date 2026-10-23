import SwiftUI

@main
struct VitalMacApp: App {
    @StateObject private var monitor = SystemMonitor()
    @StateObject private var notify = NotificationManager()

    static let mainWindowID = "main"

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            RootView()
                .environmentObject(monitor)
                .environmentObject(notify)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    monitor.start()
                    AutoMaintenance.runIfDue(notify: notify)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("VitalMac Hakkında") { }
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
