import Foundation
import CryptoKit

/// Olası yinelenen dosya grubu (aynı boyut + aynı içerik örneklemi).
struct DuplicateGroup: Identifiable, Sendable {
    var id: String { files.first?.path ?? "" }
    var fileSize: Int64       // her bir dosyanın diskte kapladığı alan
    var files: [FileEntry]
    var wasted: Int64 { fileSize * Int64(max(0, files.count - 1)) }
}

/// Yinelenen dosya bulucu. Aday listesi tam disk taramasından gelir (yeniden dolaşmaz).
enum DuplicateFinder {

    /// Adayları önce bayt uzunluğuna göre gruplar, sonra baş/orta/son 64 KB örneklerinin
    /// SHA-256 özetini karşılaştırır. Sabit bağlantılar tarayıcıda zaten tekilleştirilmiştir.
    static func find(_ candidates: [FileEntry]) async -> [DuplicateGroup] {
        var bySize: [Int64: [FileEntry]] = [:]
        for file in candidates { bySize[file.logicalSize, default: []].append(file) }
        let buckets = bySize.values.filter { $0.count > 1 }

        return await withTaskGroup(of: [DuplicateGroup].self) { group in
            for bucket in buckets {
                group.addTask {
                    if Task.isCancelled { return [] }
                    var byHash: [String: [FileEntry]] = [:]
                    for file in bucket {
                        guard let hash = sampleHash(file.path, length: file.logicalSize) else { continue }
                        byHash[hash, default: []].append(file)
                    }
                    return byHash.values.filter { $0.count > 1 }.map {
                        DuplicateGroup(fileSize: $0.map(\.size).max() ?? 0,
                                       files: $0.sorted { $0.path < $1.path })
                    }
                }
            }
            var all: [DuplicateGroup] = []
            for await part in group { all.append(contentsOf: part) }
            return all.sorted { $0.wasted > $1.wasted }
        }
    }

    /// Dosyanın baş, orta ve son 64 KB'ından özet çıkarır. Okunamazsa nil (grup dışı kalır).
    private static func sampleHash(_ path: String, length: Int64) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let chunk = 64 * 1024
        var hasher = SHA256()
        do {
            var offsets: [UInt64] = [0]
            if length > Int64(chunk * 2) { offsets.append(UInt64(length / 2)) }
            if length > Int64(chunk) { offsets.append(UInt64(max(0, length - Int64(chunk)))) }
            for offset in offsets {
                try handle.seek(toOffset: offset)
                guard let data = try handle.read(upToCount: chunk) else { break }
                hasher.update(data: data)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Kullanıcının seçtiği öğeleri güvenli biçimde Çöp Kutusu'na taşır (kalıcı silmez).
enum SafeTrash {

    enum Failure: LocalizedError {
        case protectedPath(String)
        case system(String, String)

        var errorDescription: String? {
            switch self {
            case .protectedPath(let p):
                return String(localized: "Korunan konum, çöpe taşınmadı: \(p)")
            case .system(let p, let msg):
                return String(localized: "Çöpe taşınamadı (\(p)): \(msg)")
            }
        }
    }

    /// Doğrudan çöpe taşınması engellenen ~/Library alt klasörleri (hesap, anahtar zinciri vb.).
    private static let protectedLibrary: Set<String> = [
        "Accounts", "Application Scripts", "Cookies", "Keychains", "Mail", "Messages",
        "Mobile Documents", "CloudStorage", "Preferences", "Safari", "Calendars",
        "Group Containers", "Containers", "Photos", "IdentityServices", "Sharing"
    ]

    /// Yalnızca ev klasörü altındaki, yeterince derin ve korunmayan yolları kabul eder.
    /// ~/Desktop, ~/Library gibi üst klasörler ve hassas ~/Library alanları reddedilir.
    static func isAllowed(_ path: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        guard target.hasPrefix(home + "/") else { return false }
        // Üst klasör zincirinde ev dışına çıkan bir sembolik bağ olmasın (öğenin kendisi bağ olabilir;
        // o durumda yalnızca bağ taşınır, hedefi değil).
        let parent = URL(fileURLWithPath: target).deletingLastPathComponent().resolvingSymlinksInPath().path
        let realHome = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        guard parent == realHome || parent.hasPrefix(realHome + "/") else { return false }
        let rel = target.dropFirst(home.count + 1).split(separator: "/").map(String.init)
        guard rel.count >= 2, !rel.contains("..") else { return false }
        if rel[0] == "Library" {
            guard rel.count >= 3 else { return false }
            if protectedLibrary.contains(rel[1]) {
                // Containers/Group Containers içinde yalnızca uygulama önbelleği vb. derin yollar
                return (rel[1] == "Containers" || rel[1] == "Group Containers") && rel.count >= 6
            }
        }
        return true
    }

    /// Çöpe taşır; hata durumunda açıklayıcı `Failure` fırlatır.
    static func trash(_ path: String) throws {
        guard isAllowed(path) else { throw Failure.protectedPath(path) }
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        } catch {
            throw Failure.system(path, error.localizedDescription)
        }
    }
}
