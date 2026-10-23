import Foundation
import UserNotifications
import AppKit

/// Ayar anahtarları (UserDefaults).
enum SettingsKey {
    static let notifyEnabled = "notify.enabled"
    static let notifyCPU = "notify.cpu"
    static let notifyMem = "notify.mem"
    static let notifyDisk = "notify.disk"
    static let notifyTemp = "notify.temp"
    static let autoCleanEnabled = "autoclean.enabled"
    static let autoCleanLast = "autoclean.lastDate"

    static let defaults: [String: Double] = [
        notifyCPU: 90, notifyMem: 85, notifyDisk: 90, notifyTemp: 90
    ]
    static func threshold(_ key: String) -> Double {
        let d = UserDefaults.standard
        return d.object(forKey: key) == nil ? (defaults[key] ?? 90) : d.double(forKey: key)
    }
}

/// Eşik bildirimleri ve haftalık otomatik bakım.
@MainActor
final class NotificationManager: ObservableObject {
    @Published var authorized = false
    private var lastFired: [String: Date] = [:]
    private let debounce: TimeInterval = 300   // aynı uyarı için 5 dk bekle

    /// UNUserNotificationCenter yalnızca .app paketi içinden (bundle kimliği varken) kullanılabilir;
    /// `swift run` ile çalışırken `current()` çağrısı süreci çökertir.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    /// Kullanıcı bildirimleri açtığında izin ister.
    func requestAuthorization() {
        guard let center else {
            NSLog("MacNabız: bildirimler yalnızca .app paketinden çalışırken kullanılabilir.")
            authorized = false
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("MacNabız: bildirim izni alınamadı: %@", error.localizedDescription)
            }
            Task { @MainActor in self.authorized = granted }
        }
    }

    /// Her ölçümde çağrılır; eşik aşımında (debounce ile) bildirim gönderir.
    func evaluate(_ monitor: SystemMonitor) {
        guard UserDefaults.standard.bool(forKey: SettingsKey.notifyEnabled) else { return }

        check("cpu", monitor.cpu, SettingsKey.threshold(SettingsKey.notifyCPU),
              "İşlemci yükü yüksek", "CPU kullanımı %\(Int(monitor.cpu.rounded()))")
        check("mem", monitor.memory.pressure, SettingsKey.threshold(SettingsKey.notifyMem),
              "Bellek baskısı yüksek", "Bellek %\(Int(monitor.memory.pressure.rounded())) dolu")
        check("disk", monitor.disk.usedPercent, SettingsKey.threshold(SettingsKey.notifyDisk),
              "Disk doluyor", "Disk %\(Int(monitor.disk.usedPercent.rounded())) dolu · \(Fmt.bytes(monitor.disk.free)) boş")
        if monitor.sensors.available {
            check("temp", monitor.sensors.cpuTemp, SettingsKey.threshold(SettingsKey.notifyTemp),
                  "Sıcaklık yüksek", "CPU \(Int(monitor.sensors.cpuTemp.rounded()))°C")
        }
    }

    private func check(_ id: String, _ value: Double, _ limit: Double, _ title: String, _ body: String) {
        guard value >= limit else { return }
        if let last = lastFired[id], Date().timeIntervalSince(last) < debounce { return }
        lastFired[id] = Date()
        post(id: id, title: title, body: body)
    }

    func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(id)-\(Int(Date().timeIntervalSince1970))",
            content: content, trigger: nil
        )
        guard let center else { return }
        center.add(request) { error in
            if let error {
                NSLog("MacNabız: bildirim gönderilemedi (%@): %@", id, error.localizedDescription)
            }
        }
    }
}

/// Haftalık otomatik bakım: yalnızca yeniden oluşturulabilen önbellek/log/DerivedData temizlenir
/// (çöp kutusu ve kişisel veriye dokunulmaz). Kullanıcı Ayarlar'dan açar.
enum AutoMaintenance {
    static func runIfDue(notify: NotificationManager) {
        let d = UserDefaults.standard
        guard d.bool(forKey: SettingsKey.autoCleanEnabled) else { return }
        let last = d.double(forKey: SettingsKey.autoCleanLast)
        let now = Date().timeIntervalSince1970
        if last > 0, now - last < 7 * 24 * 3600 { return }   // 7 günde bir

        // Çalışan uygulamaların önbelleklerine dokunulmaz (ana iş parçacığında okunur).
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))

        DispatchQueue.global(qos: .utility).async {
            let (moved, skipped, failed) = cleanSafe(runningBundleIDs: running)
            d.set(now, forKey: SettingsKey.autoCleanLast)
            var body = "\(Fmt.bytes(moved)) çöpe taşındı; yer, Çöp Kutusu boşaltılınca açılır."
            if skipped > 0 { body += " Açık uygulamalara ait \(skipped) önbellek atlandı." }
            if failed > 0 { body += " \(failed) öğe taşınamadı." }
            Task { @MainActor in
                notify.post(id: "autoclean", title: "Otomatik temizlik tamamlandı", body: body)
            }
        }
    }

    /// Önbellek/log/DerivedData içeriğini Çöp Kutusu'na taşır (kalıcı silmez).
    /// Açık uygulamaların önbellekleri, Apple sistem önbellekleri ve son 1 saatte değişen öğeler atlanır.
    /// (taşınan bayt, atlanan, taşınamayan) döner.
    private static func cleanSafe(runningBundleIDs: Set<String>) -> (moved: Int64, skipped: Int, failed: Int) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let dirs = [
            "Library/Caches",
            "Library/Logs",
            "Library/Developer/Xcode/DerivedData",
        ].map { home.appendingPathComponent($0) }
        let recent = Date().addingTimeInterval(-3600)

        var moved: Int64 = 0
        var skipped = 0
        var failed = 0
        for dir in dirs where fm.fileExists(atPath: dir.path) {
            let items: [URL]
            do {
                items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            } catch {
                NSLog("MacNabız otomatik temizlik: %@ okunamadı: %@", dir.path, error.localizedDescription)
                continue
            }
            for item in items {
                let name = item.lastPathComponent
                let inUse = runningBundleIDs.contains { name == $0 || name.hasPrefix($0 + ".") }
                let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if inUse || name.hasPrefix("com.apple.") || (modified.map { $0 > recent } ?? false) {
                    skipped += inUse ? 1 : 0
                    continue
                }
                let size = DiskAnalyzer.directorySize(item)
                do {
                    try SafeTrash.trash(item.path)
                    moved += size
                } catch {
                    failed += 1
                    NSLog("MacNabız otomatik temizlik: %@ taşınamadı: %@", item.path, error.localizedDescription)
                }
            }
        }
        return (moved, skipped, failed)
    }
}
