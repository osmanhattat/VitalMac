import Foundation

/// Geri kazanılabilir alan kalemi.
struct JunkItem: Identifiable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case projects   = "Proje Derleme Çıktıları"
        case devCaches  = "Geliştirici Önbellekleri"
        case xcode      = "Xcode & Simülatör"
        case android    = "Android SDK"
        case media      = "Sistem & Medya"
        case downloads  = "İndirilenler"

        var icon: String {
            switch self {
            case .projects:  return "hammer"
            case .devCaches: return "shippingbox"
            case .xcode:     return "iphone.gen3"
            case .android:   return "smartphone"
            case .media:     return "photo.on.rectangle"
            case .downloads: return "arrow.down.circle"
            }
        }
    }

    enum Safety: Sendable {
        case safe       // yeniden üretilir / yeniden indirilir
        case caution    // emin olunmalı (arşiv, eski SDK, uzun süredir kullanılmayan)

        var label: String { self == .safe ? "Güvenli" : "Kontrol et" }
    }

    /// Kalem nasıl temizlenir.
    enum Action: Sendable {
        case trash(String)                                  // yol → Çöp Kutusu
        case command(executable: String, arguments: [String])  // ör. xcrun simctl runtime delete <id>
    }

    let id: String
    let group: Group
    let title: String
    let detail: String          // yol veya açıklama
    let note: String            // ne kaybedilir?
    let safety: Safety
    let size: Int64
    let lastUsed: Date?
    let action: Action

    var revealPath: String? {
        if case .trash(let p) = action { return p }
        return nil
    }
}

/// Bilinen gereksiz/yeniden üretilebilir alanları bulur ve boyutlarını paralel ölçer.
enum SpaceSaver {

    /// Proje kökü olarak aranacak klasörler (var olanlar kullanılır).
    static var defaultProjectRoots: [String] {
        let home = NSHomeDirectory()
        return ["Desktop", "Documents", "Developer", "Projects", "Projeler", "Code", "code",
                "src", "repos", "workspace", "dev", "development", "GitHub"]
            .map { home + "/" + $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    static func scan(projectRoots: [String]) async -> [JunkItem] {
        async let fixed = scanFixedLocations()
        async let projects = scanProjects(roots: projectRoots)
        async let runtimes = simulatorRuntimes()
        async let downloads = oldInstallers()
        let all = await fixed + projects + runtimes + downloads
        return all.filter { $0.size > 1_000_000 }.sorted { $0.size > $1.size }
    }

    // MARK: Sabit konumlar

    private struct Known {
        let group: JunkItem.Group
        let title: String
        let path: String       // ~ ile başlar
        let note: String
        let safety: JunkItem.Safety
        var eachChild = false  // alt klasörleri ayrı kalem olarak listele
    }

    private static let known: [Known] = [
        // Geliştirici önbellekleri
        Known(group: .devCaches, title: String(localized: "NuGet paket önbelleği"), path: "~/.nuget/packages",
              note: String(localized: "Tüm .NET paketlerinin yerel kopyası. Sonraki `dotnet restore` gerekenleri yeniden indirir."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "NuGet HTTP önbelleği"), path: "~/.local/share/NuGet",
              note: String(localized: "NuGet indirme önbelleği. Silmek güvenlidir."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "npm önbelleği"), path: "~/.npm/_cacache",
              note: String(localized: "npm indirme önbelleği. `npm install` gerektiğinde yeniden indirir."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "pnpm deposu"), path: "~/Library/pnpm/store",
              note: String(localized: "pnpm içerik deposu. Projeler bir sonraki `pnpm install`'da yeniden bağlanır."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "Yarn önbelleği"), path: "~/Library/Caches/Yarn",
              note: String(localized: "Yarn indirme önbelleği. Silmek güvenlidir."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "Gradle önbelleği"), path: "~/.gradle/caches",
              note: String(localized: "Gradle bağımlılık/derleme önbelleği. İlk derleme yavaşlar, sonra yeniden oluşur."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "Gradle dağıtımları"), path: "~/.gradle/wrapper/dists",
              note: String(localized: "İndirilmiş Gradle sürümleri. Gerekeni wrapper yeniden indirir."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "CocoaPods önbelleği"), path: "~/Library/Caches/CocoaPods",
              note: String(localized: "Pod indirme önbelleği. Silmek güvenlidir."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "Homebrew indirmeleri"), path: "~/Library/Caches/Homebrew",
              note: String(localized: "Kurulum paketleri. `brew cleanup` ile aynı etki."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "Dart/Flutter pub önbelleği"), path: "~/.pub-cache/hosted",
              note: String(localized: "Dart paketleri. `flutter pub get` yeniden indirir."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "pip önbelleği"), path: "~/Library/Caches/pip",
              note: String(localized: "Python paket indirme önbelleği. Silmek güvenlidir."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "Maven deposu"), path: "~/.m2/repository",
              note: String(localized: "Java bağımlılıkları. Sonraki derleme yeniden indirir."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "Cargo kayıt önbelleği"), path: "~/.cargo/registry",
              note: String(localized: "Rust crate indirmeleri. Silmek güvenlidir."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "Go modül önbelleği"), path: "~/go/pkg/mod",
              note: String(localized: "Go modülleri. Yeniden indirilebilir; çevrimdışı çalışıyorsanız tutun."), safety: .caution),
        Known(group: .devCaches, title: String(localized: "Playwright tarayıcıları"), path: "~/Library/Caches/ms-playwright",
              note: String(localized: "Test tarayıcıları. `npx playwright install` ile geri gelir."), safety: .safe),
        Known(group: .devCaches, title: String(localized: "React Native önbelleği"), path: "~/Library/Caches/ReactNative",
              note: String(localized: "Metro/RN önbelleği. Silmek güvenlidir."), safety: .safe),

        // Xcode
        Known(group: .xcode, title: String(localized: "Xcode DerivedData"), path: "~/Library/Developer/Xcode/DerivedData",
              note: String(localized: "Derleme ara çıktıları. Silmek güvenlidir; ilk derleme yavaşlar."), safety: .safe),
        Known(group: .xcode, title: String(localized: "iOS DeviceSupport"), path: "~/Library/Developer/Xcode/iOS DeviceSupport",
              note: String(localized: "Bağlanan cihazlar için sembol dosyaları. Cihaz tekrar bağlanınca yeniden oluşur."), safety: .safe),
        Known(group: .xcode, title: String(localized: "Xcode Arşivleri"), path: "~/Library/Developer/Xcode/Archives",
              note: String(localized: "Yayınlanmış sürümlerin arşivleri ve dSYM'leri. Çökme raporlarını çözmek için gerekebilir."), safety: .caution),
        Known(group: .xcode, title: String(localized: "Simülatör önbellekleri"), path: "~/Library/Developer/CoreSimulator/Caches",
              note: String(localized: "Simülatör dyld önbellekleri. Silmek güvenlidir."), safety: .safe),

        // Android
        Known(group: .android, title: String(localized: "Android sistem imajları"), path: "~/Library/Android/sdk/system-images",
              note: String(localized: "Emülatör imajları. Kullanmadığınız API sürümlerini silin; Android Studio'dan yeniden indirilir."),
              safety: .caution, eachChild: true),
        Known(group: .android, title: String(localized: "Android NDK"), path: "~/Library/Android/sdk/ndk",
              note: String(localized: "NDK sürümleri. Projelerinizin kullanmadığı eski sürümleri silin."), safety: .caution, eachChild: true),
        Known(group: .android, title: String(localized: "Android emülatörleri (AVD)"), path: "~/.android/avd",
              note: String(localized: "Emülatör cihazları ve içindeki veriler."), safety: .caution, eachChild: true),
        Known(group: .android, title: String(localized: "Android önbelleği"), path: "~/.android/cache",
              note: String(localized: "SDK yöneticisi önbelleği. Silmek güvenlidir."), safety: .safe),

        // Sistem & medya
        Known(group: .media, title: String(localized: "Aerial duvar kağıdı videoları"), path: "~/Library/Application Support/com.apple.wallpaper/aerials/videos",
              note: String(localized: "İndirilmiş hareketli duvar kağıtları. Silinirse, seçtiğinizde macOS yeniden indirir."), safety: .safe),
        Known(group: .media, title: String(localized: "Mail ek indirmeleri"), path: "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
              note: String(localized: "Mail'den açılmış eklerin kopyaları. Ekler e-postada durmaya devam eder."), safety: .safe),
        Known(group: .media, title: String(localized: "iPhone/iPad yedekleri"), path: "~/Library/Application Support/MobileSync/Backup",
              note: String(localized: "Yerel cihaz yedekleri. iCloud yedeğiniz yoksa silmeyin."), safety: .caution, eachChild: true),
    ]

    private static func expand(_ path: String) -> String {
        path.hasPrefix("~") ? NSHomeDirectory() + path.dropFirst() : path
    }

    private static func scanFixedLocations() async -> [JunkItem] {
        var jobs: [(Known, String)] = []
        let fm = FileManager.default
        for k in known {
            let path = expand(k.path)
            guard fm.fileExists(atPath: path) else { continue }
            if k.eachChild {
                let children = (try? fm.contentsOfDirectory(atPath: path)) ?? []
                for c in children where !c.hasPrefix(".") { jobs.append((k, path + "/" + c)) }
            } else {
                jobs.append((k, path))
            }
        }
        return await measure(jobs) { k, path, size in
            let title = k.eachChild ? String(localized: "\(k.title) — \((path as NSString).lastPathComponent)") : k.title
            return JunkItem(id: path, group: k.group, title: title, detail: tilde(path), note: k.note,
                            safety: k.safety, size: size, lastUsed: modificationDate(path), action: .trash(path))
        }
    }

    // MARK: Proje derleme çıktıları

    /// Artık klasör adı → üst klasörde bulunması gereken işaret dosyaları (biri yeterli).
    private static let artifactMarkers: [String: [String]] = [
        "node_modules": ["package.json"],
        ".next":        ["package.json"],
        ".nuxt":        ["package.json"],
        ".angular":     ["angular.json"],
        "bin":          [".csproj", ".fsproj", ".vbproj"],
        "obj":          [".csproj", ".fsproj", ".vbproj"],
        "Pods":         ["Podfile"],
        ".dart_tool":   ["pubspec.yaml"],
        "build":        ["pubspec.yaml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
        ".gradle":      ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
        "target":       ["Cargo.toml", "pom.xml"],
        "venv":         [],   // pyvenv.cfg içerir
        ".venv":        [],
        "DerivedData":  [".xcodeproj", ".xcworkspace"],
    ]

    private static func scanProjects(roots: [String]) async -> [JunkItem] {
        let found = await Task.detached(priority: .userInitiated) { () -> [(String, String)] in
            var result: [(String, String)] = []
            for root in roots { findArtifacts(root, depth: 0, into: &result) }
            return result
        }.value

        let jobs = found.map { (path: $0.0, kind: $0.1) }
        return await measure(jobs.map { ($0.kind, $0.path) }) { kind, path, size in
            let last = modificationDate(path)
            let stale = last.map { Date().timeIntervalSince($0) > 60 * 86_400 } ?? false
            let note = stale
                ? String(localized: "60+ gündür değişmemiş. Silinirse proje bir sonraki kurulum/derlemede yeniden üretir.")
                : String(localized: "Yakın zamanda kullanılmış. Silinebilir ama bir sonraki derleme/kurulum uzun sürer.")
            return JunkItem(id: path, group: .projects, title: String(localized: "\(projectLabel(for: path)) › \(kind)"),
                            detail: tilde(path), note: note, safety: stale ? .safe : .caution,
                            size: size, lastUsed: last, action: .trash(path))
        }
    }

    /// "app", "android" gibi genel adlarda bir üst klasörü de ekler: "Proje/android/app".
    private static func projectLabel(for artifactPath: String) -> String {
        let generic: Set<String> = ["app", "android", "ios", "src", "web", "client", "server",
                                    "frontend", "backend", "api", "mobile", "packages", "apps"]
        var parts: [String] = []
        var dir = (artifactPath as NSString).deletingLastPathComponent
        while parts.count < 3 {
            let name = (dir as NSString).lastPathComponent
            guard !name.isEmpty, dir != "/" else { break }
            parts.insert(name, at: 0)
            if !generic.contains(name.lowercased()) { break }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return parts.joined(separator: "/")
    }

    /// Klasör ağacını (en fazla 6 düzey) gezip proje artıklarını bulur; artığın içine inmez.
    private static func findArtifacts(_ dir: String, depth: Int, into result: inout [(String, String)]) {
        guard depth <= 6, !Task.isCancelled,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        let entrySet = Set(entries)
        for name in entries {
            let path = dir + "/" + name
            var st = stat()
            guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { continue }   // sembolik bağları izleme
            if name == ".git" || name == ".Trash" || name.hasSuffix(".app") || name == "Library" && depth == 0 { continue }

            if let markers = artifactMarkers[name], isArtifact(name, at: path, markers: markers, siblings: entrySet) {
                result.append((path, name))
                continue
            }
            // Bilinen artık ama işareti yoksa (ör. kaynak "build" klasörü) içine inme gereği yok.
            if name == "node_modules" { continue }
            findArtifacts(path, depth: depth + 1, into: &result)
        }
    }

    private static func isArtifact(_ name: String, at path: String, markers: [String], siblings: Set<String>) -> Bool {
        if name == "venv" || name == ".venv" {
            return FileManager.default.fileExists(atPath: path + "/pyvenv.cfg")
        }
        return markers.contains { marker in
            marker.hasPrefix(".") && !marker.dropFirst().contains(".")
                ? siblings.contains { $0.hasSuffix(marker) }      // uzantı (ör. .csproj)
                : siblings.contains(marker)
        }
    }

    // MARK: Simülatör runtime'ları

    private struct RuntimeInfo: Decodable {
        let identifier: String
        let version: String?
        let build: String?
        let sizeBytes: Int64?
        let lastUsedAt: String?
        let deletable: Bool?
        let platformIdentifier: String?
    }

    /// `xcrun simctl runtime list -j` — sistem tarafında (AssetsV2) duran, klasör taramasında
    /// görünmeyen büyük iOS/watchOS runtime imajları.
    private static func simulatorRuntimes() async -> [JunkItem] {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun") else { return [] }
        let output: Data
        do {
            output = try await ProcessRunner.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"], timeout: 30)
        } catch {
            NSLog("VitalMac: simülatör runtime listesi alınamadı: %@", error.localizedDescription)
            return []
        }
        guard let dict = try? JSONDecoder().decode([String: RuntimeInfo].self, from: output) else { return [] }

        let iso = ISO8601DateFormatter()
        let runtimes = dict.values.filter { $0.deletable != false }
        // Aynı platformdaki en yeni sürüm "güvenli değil" sayılır (muhtemelen kullanılıyor).
        let newest = Dictionary(grouping: runtimes) { $0.platformIdentifier ?? "" }
            .compactMapValues { $0.max { ($0.version ?? "").compare($1.version ?? "", options: .numeric) == .orderedAscending }?.identifier }

        return runtimes.map { rt in
            let platform = (rt.platformIdentifier ?? "").contains("watch") ? "watchOS"
                : (rt.platformIdentifier ?? "").contains("tv") ? "tvOS"
                : (rt.platformIdentifier ?? "").contains("xr") ? "visionOS" : "iOS"
            let isNewest = newest.values.contains(rt.identifier)
            return JunkItem(
                id: "runtime:" + rt.identifier, group: .xcode,
                title: String(localized: "\(platform) \(rt.version ?? "?") simülatör runtime'ı"),
                detail: "Build \(rt.build ?? "?") · xcrun simctl runtime delete",
                note: isNewest
                    ? String(localized: "Bu platformun en yeni runtime'ı; simülatör kullanıyorsanız tutun.")
                    : String(localized: "Daha yeni bir sürüm yüklü. Eski runtime'ı silmek güvenlidir; Xcode'dan yeniden indirilebilir."),
                safety: isNewest ? .caution : .safe,
                size: rt.sizeBytes ?? 0,
                lastUsed: rt.lastUsedAt.flatMap { iso.date(from: $0) },
                action: .command(executable: "/usr/bin/xcrun", arguments: ["simctl", "runtime", "delete", rt.identifier])
            )
        }
    }

    // MARK: İndirilenler

    private static func oldInstallers() async -> [JunkItem] {
        let dir = NSHomeDirectory() + "/Downloads"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        let exts: Set<String> = ["dmg", "pkg", "xip", "iso", "zip", "msi", "exe", "apk", "ipa"]
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let jobs: [(String, String)] = names.compactMap { name in
            let ext = (name as NSString).pathExtension.lowercased()
            guard exts.contains(ext) else { return nil }
            let path = dir + "/" + name
            guard let date = modificationDate(path), date < cutoff else { return nil }
            return (ext, path)
        }
        return await measure(jobs) { ext, path, size in
            JunkItem(id: path, group: .downloads, title: (path as NSString).lastPathComponent,
                     detail: tilde(path),
                     note: ext == "zip"
                        ? String(localized: "30+ gün önce indirilmiş arşiv. Açtıysanız ve içeriği yerindeyse silebilirsiniz.")
                        : String(localized: "30+ gün önce indirilmiş kurulum dosyası. Kurulum yapıldıysa gerek yok."),
                     safety: ext == "zip" ? .caution : .safe, size: size,
                     lastUsed: modificationDate(path), action: .trash(path))
        }
    }

    // MARK: Yardımcılar

    /// Yolların boyutunu paralel ölçüp kaleme çevirir.
    private static func measure<K: Sendable>(_ jobs: [(K, String)],
                                             make: @escaping @Sendable (K, String, Int64) -> JunkItem) async -> [JunkItem] {
        await withTaskGroup(of: JunkItem?.self) { group in
            for (key, path) in jobs {
                group.addTask {
                    if Task.isCancelled { return nil }
                    return make(key, path, DiskScanner.allocatedSize(path))
                }
            }
            var items: [JunkItem] = []
            for await item in group { if let item { items.append(item) } }
            return items
        }
    }

    static func modificationDate(_ path: String) -> Date? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
    }

    static func tilde(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// Harici komutu argüman dizisiyle (kabuk YOK → enjeksiyon yok) çalıştırır.
enum ProcessRunner {

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Çıktıyı döndürür; sıfır dışı çıkış kodunda stderr ile birlikte hata fırlatır.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err

            // Boru tamponu dolup kilitlenmesin diye çıktılar eşzamanlı okunur.
            let outBox = DataBox(), errBox = DataBox()
            out.fileHandleForReading.readabilityHandler = { h in outBox.append(h.availableData) }
            err.fileHandleForReading.readabilityHandler = { h in errBox.append(h.availableData) }

            do { try process.run() } catch {
                throw Failure(message: String(localized: "\(executable) çalıştırılamadı: \(error.localizedDescription)"))
            }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                if Date() > deadline || Task.isCancelled {
                    process.terminate()
                    process.waitUntilExit()
                    let command = (executable as NSString).lastPathComponent + " " + arguments.joined(separator: " ")
                    throw Failure(message: String(localized: "Komut zaman aşımına uğradı: \(command)"))
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            outBox.append(out.fileHandleForReading.readDataToEndOfFile())
            errBox.append(err.fileHandleForReading.readDataToEndOfFile())

            guard process.terminationStatus == 0 else {
                let msg = String(data: errBox.data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw Failure(message: msg.isEmpty ? String(localized: "Komut başarısız (kod \(process.terminationStatus)).") : msg)
            }
            return outBox.data
        }.value
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()
        func append(_ d: Data) { lock.lock(); storage.append(d); lock.unlock() }
        var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
    }
}

/// "Alan Kazan" sayfasının durumu; RootView'da tek örnek yaşar.
@MainActor
final class SpaceSaverStore: ObservableObject {
    @Published private(set) var items: [JunkItem] = []
    @Published private(set) var scanning = false
    @Published private(set) var working = false
    @Published private(set) var scannedAt: Date?
    @Published var selected: Set<String> = []
    @Published var message: String?
    @Published var projectRoots: [String] = SpaceSaver.defaultProjectRoots

    private var task: Task<Void, Never>?

    var selectedItems: [JunkItem] { items.filter { selected.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var safeSize: Int64 { items.filter { $0.safety == .safe }.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    func scan() {
        guard !scanning else { return }
        scanning = true
        message = nil
        let roots = projectRoots
        task = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                await SpaceSaver.scan(projectRoots: roots)
            }.value
            guard let self else { return }
            self.items = found
            // Varsayılan seçim: yalnızca "güvenli" ve komut gerektirmeyen kalemler.
            self.selected = Set(found.filter {
                if case .trash = $0.action { return $0.safety == .safe }
                return false
            }.map(\.id))
            self.scannedAt = Date()
            self.scanning = false
        }
    }

    func addProjectRoot(_ path: String) {
        guard !projectRoots.contains(path) else { return }
        projectRoots.append(path)
        scan()
    }

    /// Seçili "çöpe taşı" kalemlerini taşır; hataları tek tek raporlar.
    func trashSelected() {
        let targets = selectedItems.compactMap { item -> (String, JunkItem)? in
            if case .trash(let p) = item.action { return (p, item) }
            return nil
        }
        guard !targets.isEmpty, !working else { return }
        working = true
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> (freed: Int64, done: [String], errors: [String]) in
                var freed: Int64 = 0
                var done: [String] = []
                var errors: [String] = []
                for (path, item) in targets {
                    do {
                        try SafeTrash.trash(path)
                        freed += item.size
                        done.append(item.id)
                    } catch {
                        errors.append(error.localizedDescription)
                    }
                }
                return (freed, done, errors)
            }.value
            guard let self else { return }
            self.items.removeAll { outcome.done.contains($0.id) }
            self.selected.subtract(outcome.done)
            self.working = false
            var text = String(localized: "\(outcome.done.count) öğe çöpe taşındı (\(Fmt.bytes(outcome.freed))). Yer, Çöp Kutusu boşaltılınca açılır.")
            if !outcome.errors.isEmpty {
                text += String(localized: "\n\(outcome.errors.count) öğe taşınamadı: ") + outcome.errors.prefix(3).joined(separator: " · ")
            }
            self.message = text
        }
    }

    /// Komutla temizlenen kalemi çalıştırır (ör. eski simülatör runtime'ını sil).
    func runCommand(_ item: JunkItem) {
        guard case .command(let exe, let args) = item.action, !working else { return }
        working = true
        Task { [weak self] in
            let result: String
            var succeeded = false
            do {
                _ = try await ProcessRunner.run(exe, args, timeout: 600)
                succeeded = true
                result = String(localized: "\(item.title) kaldırıldı (\(Fmt.bytes(item.size))).")
            } catch {
                result = String(localized: "\(item.title) kaldırılamadı: \(error.localizedDescription)")
            }
            guard let self else { return }
            if succeeded { self.items.removeAll { $0.id == item.id } }
            self.working = false
            self.message = result
        }
    }

    /// Çöp Kutusu'nu boşaltır (Finder üzerinden; kullanıcı onayı arayüzde alınır).
    func emptyTrash() {
        guard !working else { return }
        working = true
        Task { [weak self] in
            var text: String
            do {
                _ = try await ProcessRunner.run("/usr/bin/osascript",
                                                ["-e", "tell application \"Finder\" to empty trash"], timeout: 900)
                text = String(localized: "Çöp Kutusu boşaltıldı.")
            } catch {
                text = String(localized: "Çöp Kutusu boşaltılamadı: \(error.localizedDescription)")
            }
            self?.working = false
            self?.message = text
        }
    }
}
