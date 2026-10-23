import Foundation

/// Temizlenebilir bir hedef (önbellek/log/çöp klasörü) + içerik dökümü.
struct CleanTarget: Identifiable {
    let id = UUID()
    var name: String
    var detail: String        // konum açıklaması (örn. "~/Library/Caches içeriği")
    var note: String          // güvenlik açıklaması (ne kaybedilir / risk)
    var path: URL
    var size: Int64
    var enabled: Bool
    var items: [DiskItem]     // silinecek öğelerin dökümü (büyükten küçüğe)
}

/// Güvenli temizlik: kullanıcı önbelleği, loglar, Xcode DerivedData ve çöp kutusu.
/// Silme işlemi YALNIZCA kullanıcı arayüzde onayladıktan sonra `cleanSelected()` ile yapılır
/// ve tam olarak listede gösterilen öğeleri siler.
@MainActor
final class CacheCleaner: ObservableObject {
    @Published var targets: [CleanTarget] = []
    @Published var scanning = false
    @Published var lastFreed: Int64 = 0
    @Published private(set) var cleaning = false

    func scan() {
        scanning = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [(name: String, detail: String, note: String, url: URL)] = [
            ("Kullanıcı Önbelleği", "~/Library/Caches",
             "Uygulamaların geçici dosyaları. Silmek güvenlidir; uygulamalar gerektiğinde yeniden oluşturur.",
             home.appendingPathComponent("Library/Caches")),
            ("Uygulama Logları", "~/Library/Logs",
             "Tanılama günlükleri. Silmek güvenlidir.",
             home.appendingPathComponent("Library/Logs")),
            ("Xcode DerivedData", "~/Library/Developer/Xcode/DerivedData",
             "Derleme ara çıktıları. Silmek güvenlidir; sonraki derlemede yeniden oluşur (ilk derleme yavaşlar).",
             home.appendingPathComponent("Library/Developer/Xcode/DerivedData")),
            ("Çöp Kutusu", "~/.Trash",
             "Çöpteki öğeler kalıcı olarak silinir. Geri alınamaz.",
             home.appendingPathComponent(".Trash")),
        ]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard self != nil else { return }
            var found: [CleanTarget] = []
            for c in candidates {
                guard FileManager.default.fileExists(atPath: c.url.path) else { continue }
                let items = DiskAnalyzer.topLevel(c.url)
                let total = items.reduce(0) { $0 + $1.size }
                guard total > 0 else { continue }
                found.append(CleanTarget(
                    name: c.name, detail: c.detail, note: c.note,
                    path: c.url, size: total, enabled: true, items: items
                ))
            }
            DispatchQueue.main.async {
                self?.targets = found
                self?.scanning = false
            }
        }
    }

    /// Seçili hedeflerin —taramada listelenen— öğelerini arka planda siler.
    /// Bitince ana iş parçacığında boşaltılan bayt ve silinemeyen öğelerin listesiyle `completion` çağrılır.
    func cleanSelected(completion: @escaping (_ freed: Int64, _ failures: [String]) -> Void) {
        guard !cleaning else { return }
        cleaning = true
        let items = selectedItems()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var freed: Int64 = 0
            var failures: [String] = []
            let fm = FileManager.default
            for item in items {
                do {
                    try fm.removeItem(at: item.url)
                    freed += item.size
                } catch {
                    // Kullanımdaki/kilitli öğeler atlanır ama kullanıcıya bildirilir.
                    failures.append("\(item.name): \(error.localizedDescription)")
                    NSLog("MacNabız temizlik: silinemedi %@ — %@", item.url.path, error.localizedDescription)
                }
            }
            DispatchQueue.main.async {
                self?.lastFreed = freed
                self?.cleaning = false
                completion(freed, failures)
            }
        }
    }

    /// Yalnızca seçili hedeflerdeki tüm öğeleri (önizleme için) düz liste olarak döndürür.
    func selectedItems() -> [DiskItem] {
        targets.filter { $0.enabled }.flatMap { $0.items }
    }
}
