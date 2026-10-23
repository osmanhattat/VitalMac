#if DEBUG
import SwiftUI
import AppKit

/// Yalnızca DEBUG derlemede: `MACNABIZ_SNAPSHOT=<klasör>` ortam değişkeni verilirse her sayfayı
/// sırayla açar, uygulamanın kendi penceresini PNG olarak kaydeder ve çıkar.
/// Ekran kaydı izni gerektirmez (yalnızca kendi görünüm hiyerarşisini çizer).
@MainActor
enum SnapshotRunner {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["MACNABIZ_SNAPSHOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func run(select: @escaping (SidebarItem) -> Void,
                    render: (SidebarItem) -> AnyView, sidebar: AnyView) async {
        guard let dir = directory else { return }
        let appearance = ProcessInfo.processInfo.environment["MACNABIZ_APPEARANCE"] == "light"
            ? NSAppearance(named: .aqua) : NSAppearance(named: .darkAqua)
        NSApp.appearance = appearance
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(2))
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.setContentSize(NSSize(width: 1240, height: 820))
        }
        let only = ProcessInfo.processInfo.environment["MACNABIZ_PAGES"]?.split(separator: ",").map(String.init)
        for (index, item) in SidebarItem.allCases.enumerated() {
            if let only, !only.contains("\(index)") { continue }
            select(item)
            try? await Task.sleep(for: .seconds(item == .disk || item == .spaceSaver ? 30 : 4))
            // SwiftUI içeriği ekran dışında çiz (katmanlı görünümler cacheDisplay ile yakalanmıyor).
            let renderer = ImageRenderer(content: render(item)
                .frame(width: 1020, height: 1500, alignment: .top)
                .background(Theme.canvas)
                .environment(\.colorScheme, appearance?.name == .aqua ? .light : .dark))
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent(String(format: "r%02d.png", index)))
            }
            guard let view = NSApp.windows.first(where: { $0.canBecomeMain })?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = String(format: "%02d.png", index)
            do {
                try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            } catch {
                NSLog("MacNabız snapshot yazılamadı: %@", error.localizedDescription)
            }
        }
        let side = ImageRenderer(content: sidebar.environment(\.colorScheme, appearance?.name == .aqua ? .light : .dark))
        side.scale = 2
        if let tiff = side.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("sidebar.png"))
        }
        NSApp.terminate(nil)
    }
}
/// Görüntü alma için kenar çubuğunun SwiftUI ile çizilmiş eşi (gerçek kenar çubuğu AppKit listesidir
/// ve ekran dışında çizilemez). Aynı grupları, ikonları ve bileşenleri kullanır.
struct SnapshotSidebar: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarBrand().padding(.top, 10)
            ForEach(SidebarItem.groups, id: \.title) { group in
                Eyebrow(group.title, size: 9.5)
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
                ForEach(group.items) { item in
                    HStack(spacing: 9) {
                        Image(systemName: item.icon).frame(width: 18)
                            .foregroundStyle(item == .dashboard ? Color.white : Theme.pulse)
                        Text(item.rawValue)
                            .foregroundStyle(item == .dashboard ? Color.white : Theme.ink)
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(item == .dashboard ? Theme.pulse : .clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(.horizontal, 8)
                }
            }
            Spacer()
            MiniStatusBar()
        }
        .background(Theme.inset)
    }
}
#endif
