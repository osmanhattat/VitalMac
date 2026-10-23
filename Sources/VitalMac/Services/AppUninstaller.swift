import Foundation
import AppKit

/// /Applications içinde kurulu bir uygulama.
struct InstalledApp: Identifiable {
    let id = UUID()
    var name: String
    var url: URL
    var bundleId: String?
    var size: Int64
    var icon: NSImage?
}

/// Uygulama kaldırıcı: uygulamayı ve ona ait artık dosyaları bulur, çöpe taşır.
/// Taşıma işlemi YALNIZCA kullanıcı onayından sonra `moveToTrash()` ile yapılır.
@MainActor
final class AppUninstaller: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var scanning = false

    private let fm = FileManager.default

    /// Kaldırılması engellenen uygulamalar için gerekçe (Apple sistem uygulamaları, VitalMac'ın kendisi).
    func protectionReason(for app: InstalledApp) -> String? {
        if let bid = app.bundleId?.lowercased() {
            if bid.hasPrefix("com.apple.") { return String(localized: "Apple sistem uygulaması kaldırılamaz.") }
            if bid == Bundle.main.bundleIdentifier?.lowercased() { return String(localized: "VitalMac kendini kaldıramaz.") }
        }
        if app.url.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL {
            return String(localized: "VitalMac kendini kaldıramaz.")
        }
        return nil
    }

    /// Uygulama şu an çalışıyor mu? (Çalışan uygulamayı çöpe taşımak veri kaybına yol açabilir.)
    func isRunning(_ app: InstalledApp) -> Bool {
        let target = app.url.standardizedFileURL
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL == target
        }
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            let dirs = [
                URL(fileURLWithPath: "/Applications"),
                fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            ]
            var urls: [URL] = []
            for dir in dirs {
                guard fm.fileExists(atPath: dir.path) else { continue }
                do {
                    urls += try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                } catch {
                    NSLog("VitalMac: %@ okunamadı: %@", dir.path, error.localizedDescription)
                }
            }

            var result: [InstalledApp] = []
            for url in urls where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let size = DiskAnalyzer.directorySize(url)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                result.append(InstalledApp(
                    name: name, url: url, bundleId: bundle?.bundleIdentifier,
                    size: size, icon: icon
                ))
            }
            result.sort { $0.size > $1.size }
            DispatchQueue.main.async {
                self?.apps = result
                self?.scanning = false
            }
        }
    }

    /// Uygulamaya ait artık dosyaları (~/Library altında) bulur.
    /// İlk öğe her zaman uygulamanın kendisidir.
    ///
    /// Eşleştirme bilinçli olarak sıkıdır: yalnızca öğe adı (bilinen uzantılar atılınca)
    /// bundle kimliğine ya da uygulama adına BİREBİR eşitse veya `<bundleId>.` ile başlıyorsa
    /// eşleşir. Alt dize eşleşmesi ("Arc" → "Archive Utility") başka uygulamaların
    /// verisini çöpe taşıyabileceğinden kullanılmaz.
    func relatedFiles(for app: InstalledApp) -> [URL] {
        var found: [URL] = [app.url]
        let home = fm.homeDirectoryForCurrentUser
        let searchDirs = [
            "Library/Application Support",
            "Library/Caches",
            "Library/Preferences",
            "Library/Logs",
            "Library/Containers",
            "Library/Saved Application State",
            "Library/HTTPStorages",
            "Library/WebKit",
        ]
        let bundleId = app.bundleId?.lowercased()
        let name = app.name.lowercased()
        // Çok kısa/genel adlar (örn. "Go", "VLC" değil ama "X") yanlış eşleşmeye açıktır.
        let nameUsable = name.count >= 3
        let strippedExtensions: Set<String> = ["plist", "savedstate", "binarycookies", "log"]

        for dir in searchDirs {
            let base = home.appendingPathComponent(dir)
            guard fm.fileExists(atPath: base.path) else { continue }
            let items: [URL]
            do {
                items = try fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
            } catch {
                NSLog("VitalMac: %@ okunamadı: %@", base.path, error.localizedDescription)
                continue
            }
            for item in items {
                var n = item.lastPathComponent.lowercased()
                if strippedExtensions.contains((n as NSString).pathExtension) {
                    n = (n as NSString).deletingPathExtension
                }
                let matches: Bool
                if let bundleId, n == bundleId || n.hasPrefix(bundleId + ".") {
                    matches = true
                } else {
                    matches = nameUsable && n == name
                }
                if matches { found.append(item) }
            }
        }
        return found
    }

    /// Verilen URL'leri çöp kutusuna taşır (geri alınabilir). Onay UI'da alınır.
    /// Güvenlik: yalnızca uygulama klasörleri ve kullanıcının ~/Library alanındaki
    /// öğeler taşınır; bunların dışındaki her yol reddedilir.
    func moveToTrash(_ urls: [URL]) -> (moved: Int, errors: String) {
        var moved = 0
        var errors = ""
        for url in urls {
            guard isAllowedTarget(url) else {
                errors += String(localized: "\(url.path): izin verilen konumların dışında, atlandı.\n")
                continue
            }
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
                moved += 1
            } catch {
                errors += String(localized: "\(url.lastPathComponent): \(error.localizedDescription)\n")
            }
        }
        return (moved, errors)
    }

    private func isAllowedTarget(_ url: URL) -> Bool {
        // Sembolik bağları çözmeden (bağın kendisi taşınır) standart yol üzerinden kontrol.
        let path = url.standardizedFileURL.path
        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        let allowedRoots = ["/Applications/", home + "/Applications/", home + "/Library/"]
        guard allowedRoots.contains(where: { path.hasPrefix($0) }) else { return false }
        // Kök klasörlerin kendisi (örn. ~/Library/Caches) asla hedef olamaz.
        let parent = url.standardizedFileURL.deletingLastPathComponent().path + "/"
        if parent == home + "/" || parent == home + "/Library/" { return false }
        return !path.contains("/../")
    }
}
