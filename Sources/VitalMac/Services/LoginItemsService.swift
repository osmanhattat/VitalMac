import Foundation
import ServiceManagement

/// ~/Library/LaunchAgents içindeki bir başlangıç ajanı.
struct LaunchAgentItem: Identifiable {
    var id: String { path.path }    // yol sabittir; yenilemede seçim/durum kaybolmaz
    var label: String               // plist içindeki "Label" (yoksa dosya adı)
    var path: URL
    var loaded: Bool                // şu an launchd'ye yüklü mü
}

/// Başlangıç öğeleri yönetimi: uygulamanın kendi "girişte aç" ayarı ve
/// kullanıcı LaunchAgents listesi.
@MainActor
final class LoginItemsService: ObservableObject {
    @Published var agents: [LaunchAgentItem] = []
    @Published var launchAtLogin = false
    @Published var loading = false
    @Published var busyAgents = Set<String>()
    @Published var lastError: String?

    func refresh() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.readAgents()
            Task { @MainActor in
                guard let self else { return }
                self.agents = result.items
                if let error = result.error { self.lastError = error }
                self.loading = false
            }
        }
    }

    /// Uygulamanın girişte otomatik açılmasını ayarlar.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = String(localized: "Girişte açma ayarlanamadı: \(error.localizedDescription) (ad-hoc imzalı yapılarda bu beklenebilir).")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Bir LaunchAgent'ı etkinleştirir/devre dışı bırakır (launchctl load/unload -w).
    /// `-w` kalıcı geçersiz kılmayı yazar; böylece sonraki oturumlarda da geçerli olur.
    func setAgent(_ item: LaunchAgentItem, enabled: Bool) {
        guard !busyAgents.contains(item.id) else { return }
        busyAgents.insert(item.id)
        let action = enabled ? "load" : "unload"
        let path = item.path.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (status, output) = Privileged.runShell("/bin/launchctl", [action, "-w", path])
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                guard let self else { return }
                self.busyAgents.remove(item.id)
                // launchctl load/unload hata durumunda bile 0 dönebilir; çıktıyı da dikkate al.
                if status != 0 || trimmed.localizedCaseInsensitiveContains("error")
                    || trimmed.localizedCaseInsensitiveContains("failed") {
                    let detail = trimmed.isEmpty ? String(localized: "kod \(status)") : trimmed
                    self.lastError = enabled
                        ? String(localized: "\(item.label) etkinleştirilemedi: \(detail)")
                        : String(localized: "\(item.label) durdurulamadı: \(detail)")
                } else {
                    self.lastError = nil
                }
                self.refresh()
            }
        }
    }

    // MARK: - Okuma (arka plan)

    nonisolated private static func readAgents() -> (items: [LaunchAgentItem], error: String?) {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        guard fm.fileExists(atPath: dir.path) else { return ([], nil) }

        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        } catch {
            return ([], String(localized: "LaunchAgents okunamadı: \(error.localizedDescription)"))
        }

        let loadedLabels = currentlyLoadedLabels()
        let items = urls
            .filter { $0.pathExtension == "plist" }
            .map { url -> LaunchAgentItem in
                let fileLabel = url.deletingPathExtension().lastPathComponent
                let plist = NSDictionary(contentsOf: url)
                let label = (plist?["Label"] as? String) ?? fileLabel
                return LaunchAgentItem(label: label, path: url, loaded: loadedLabels.contains(label))
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        return (items, nil)
    }

    /// `launchctl list` çıktısındaki (PID  Durum  Etiket) etiketleri döndürür.
    nonisolated private static func currentlyLoadedLabels() -> Set<String> {
        let (status, output) = Privileged.runShell("/bin/launchctl", ["list"])
        guard status == 0 else {
            NSLog("VitalMac: launchctl list başarısız (%d): %@", status, output)
            return []
        }
        var labels = Set<String>()
        for line in output.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            if cols.count >= 3 { labels.insert(String(cols[2])) }
        }
        return labels
    }
}
