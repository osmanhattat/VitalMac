import Foundation
import Darwin
import os

// MARK: - Model

/// Taranmış bir dosya (yol + ayrılan alan + mantıksal boyut).
struct FileEntry: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let size: Int64          // diskte ayrılan alan (st_blocks * 512)
    let logicalSize: Int64   // dosyanın bayt cinsinden uzunluğu (st_size)

    var name: String { (path as NSString).lastPathComponent }
    var url: URL { URL(fileURLWithPath: path) }
}

/// Taranmış bir klasör düğümü.
///
/// İş parçacığı kuralı: düğüm, onu üreten tarama görevi tarafından doldurulur ve
/// teslim edildikten sonra YALNIZCA ana iş parçacığında (DiskScanStore) değiştirilir.
final class DirNode: Identifiable, @unchecked Sendable {
    let path: String
    let level: Int
    var size: Int64 = 0
    var fileCount: Int = 0
    var children: [DirNode] = []        // boyuta göre azalan
    var files: [FileEntry] = []         // doğrudan içerdiği en büyük dosyalar (sınırlı)
    var otherFilesSize: Int64 = 0       // listelenmeyen doğrudan dosyaların toplamı
    var otherFilesCount: Int = 0
    /// Alt klasörleri saklandı mı? (Derinlik sınırında `false`; içine inmek alt tarama gerektirir.)
    var isComplete = true
    /// Okunamayan (izin verilmeyen) alt klasör sayısı.
    var unreadable = 0

    var id: String { path }
    var name: String {
        let n = (path as NSString).lastPathComponent
        return n.isEmpty ? "/" : n
    }
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    init(path: String, level: Int) {
        self.path = path
        self.level = level
    }

    /// Alt klasör + dosya karışık, boyuta göre sıralı içerik.
    var entries: [DiskEntry] {
        var all = children.map { DiskEntry.folder($0) } + files.map { DiskEntry.file($0) }
        if otherFilesCount > 0 {
            all.append(.others(count: otherFilesCount, size: otherFilesSize, parent: path))
        }
        return all.sorted { $0.size > $1.size }
    }

    /// Bu düğümün ve alt ağacının içeriğini başka (yeni taranmış) bir düğümle değiştirir.
    func adopt(_ other: DirNode) {
        size = other.size
        fileCount = other.fileCount
        children = other.children
        files = other.files
        otherFilesSize = other.otherFilesSize
        otherFilesCount = other.otherFilesCount
        isComplete = other.isComplete
        unreadable = other.unreadable
    }
}

/// Liste/treemap'te gösterilen tek satır.
enum DiskEntry: Identifiable {
    case folder(DirNode)
    case file(FileEntry)
    case others(count: Int, size: Int64, parent: String)

    var id: String {
        switch self {
        case .folder(let n): return "d:" + n.path
        case .file(let f): return "f:" + f.path
        case .others(_, _, let p): return "o:" + p
        }
    }
    var size: Int64 {
        switch self {
        case .folder(let n): return n.size
        case .file(let f): return f.size
        case .others(_, let s, _): return s
        }
    }
    var name: String {
        switch self {
        case .folder(let n): return n.name
        case .file(let f): return f.name
        case .others(let c, _, _): return String(localized: "\(c) küçük dosya")
        }
    }
    var path: String? {
        switch self {
        case .folder(let n): return n.path
        case .file(let f): return f.path
        case .others: return nil
        }
    }
}

/// Tam taramanın sonucu.
struct ScanResult: Sendable {
    let root: DirNode
    let largest: [FileEntry]
    let duplicateCandidates: [FileEntry]
    let fileCount: Int
    let unreadable: Int
    let duration: TimeInterval
}

// MARK: - Canlı ilerleme

/// Tarama sırasında ana iş parçacığının periyodik okuduğu, kilitli sayaçlar.
final class ScanProgress: @unchecked Sendable {
    struct Snapshot {
        var files = 0
        var bytes: Int64 = 0
        var current = ""
        var topSizes: [String: Int64] = [:]   // kök altındaki birinci düzey öğe adı → biriken boyut
    }

    private let lock = OSAllocatedUnfairLock(initialState: Snapshot())

    var snapshot: Snapshot { lock.withLock { $0 } }

    func add(files: Int, bytes: Int64, top: String?, current: String?) {
        lock.withLock { s in
            s.files += files
            s.bytes += bytes
            if let top { s.topSizes[top, default: 0] += bytes }
            if let current { s.current = current }
        }
    }
}

// MARK: - Tarayıcı

/// `fts(3)` tabanlı, paralel, hızlı disk tarayıcı.
///
/// Neden hızlı: FileManager.enumerator + resourceValues yerine doğrudan `fts_read`/`lstat`
/// kullanır; ilk `splitDepth` düzeydeki klasörleri ayrı görevlere bölerek tüm çekirdeklerde
/// paralel tarar; tek geçişte klasör ağacı, en büyük dosyalar ve yinelenen adaylarını toplar.
enum DiskScanner {

    struct Options: Sendable {
        var includeHidden = true
        /// Ağaçta saklanacak en derin düzey (kök = 0). Daha derini boyuta katılır ama saklanmaz.
        var storeDepth = 5
        /// Bu düzeye kadar klasörler elle listelenip paralel görevlere bölünür.
        var splitDepth = 3
        var filesPerNode = 12
        var largestLimit = 200
        var duplicateMinSize: Int64 = 1_000_000
        var duplicateCandidateCap = 400_000
    }

    /// Kökü tarar. İptal edilirse kısmi sonuç döner (çağıran `Task.isCancelled` ile ayırt eder).
    static func scan(_ root: URL, options: Options = Options(),
                     progress: ScanProgress) async -> ScanResult {
        let start = Date()
        let rootPath = root.standardizedFileURL.path
        var st = stat()
        guard lstat(rootPath, &st) == 0 else {
            let node = DirNode(path: rootPath, level: 0)
            node.unreadable = 1
            return ScanResult(root: node, largest: [], duplicateCandidates: [], fileCount: 0,
                              unreadable: 1, duration: 0)
        }
        let ctx = Context(options: options, device: st.st_dev, progress: progress)
        let partial = await scanDirectory(rootPath, level: 0, top: nil, ctx: ctx)

        return ScanResult(
            root: partial.node,
            largest: partial.largest.sortedDescending(),
            duplicateCandidates: partial.dupCandidates,
            fileCount: partial.node.fileCount,
            unreadable: partial.unreadable,
            duration: Date().timeIntervalSince(start)
        )
    }

    /// Bir klasörün toplam ayrılan alanını hızlıca hesaplar (ağaç saklamaz).
    static func allocatedSize(_ path: String) -> Int64 {
        var st = stat()
        guard lstat(path, &st) == 0 else { return 0 }
        guard (st.st_mode & S_IFMT) == S_IFDIR else { return st.st_blocks * 512 }
        var opts = Options()
        opts.storeDepth = 0
        opts.largestLimit = 0
        opts.duplicateMinSize = .max
        let ctx = Context(options: opts, device: st.st_dev, progress: nil)
        return ftsUnit(path, baseLevel: 0, top: nil, ctx: ctx).node.size
    }

    // MARK: İç yapı

    fileprivate struct Context: Sendable {
        let options: Options
        let device: dev_t
        let progress: ScanProgress?
    }

    fileprivate struct Partial: Sendable {
        let node: DirNode
        var largest: TopFiles
        var dupCandidates: [FileEntry]
        var unreadable: Int
    }

    /// `splitDepth`'e kadar elle listeler, alt klasörleri paralel görevlere dağıtır.
    private static func scanDirectory(_ path: String, level: Int, top: String?,
                                      ctx: Context) async -> Partial {
        if level >= ctx.options.splitDepth || Task.isCancelled {
            return ftsUnit(path, baseLevel: level, top: top, ctx: ctx)
        }

        let node = DirNode(path: path, level: level)
        var largest = TopFiles(limit: ctx.options.largestLimit)
        var directFiles = TopFiles(limit: ctx.options.filesPerNode)
        var dups: [FileEntry] = []
        var unreadable = 0

        guard let listing = listDirectory(path) else {
            node.unreadable = 1
            return Partial(node: node, largest: largest, dupCandidates: [], unreadable: 1)
        }

        var subdirs: [(path: String, name: String)] = []
        var bytes: Int64 = 0
        var count = 0
        for entry in listing {
            if !ctx.options.includeHidden && entry.name.hasPrefix(".") { continue }
            let full = path == "/" ? "/" + entry.name : path + "/" + entry.name
            let st = entry.stat
            let type = st.st_mode & S_IFMT
            if type == S_IFDIR {
                // Başka birime (ör. /Volumes) geçme. Alt klasör kendi bloğunu kendi taramasında sayar.
                if st.st_dev == ctx.device { subdirs.append((full, entry.name)) }
            } else {
                let size = st.st_blocks * 512
                let file = FileEntry(path: full, size: size, logicalSize: st.st_size)
                bytes += size
                count += 1
                if type == S_IFREG {
                    if !directFiles.insert(file) { node.otherFilesSize += size; node.otherFilesCount += 1 }
                    largest.insert(file)
                    if st.st_size >= ctx.options.duplicateMinSize { dups.append(file) }
                } else {
                    node.otherFilesSize += size
                    node.otherFilesCount += 1
                }
            }
        }
        ctx.progress?.add(files: count, bytes: bytes, top: top, current: nil)

        let children = await withTaskGroup(of: Partial.self) { group in
            for sub in subdirs {
                let childTop = top ?? sub.name
                group.addTask { await scanDirectory(sub.path, level: level + 1, top: childTop, ctx: ctx) }
            }
            var results: [Partial] = []
            results.reserveCapacity(subdirs.count)
            for await r in group { results.append(r) }
            return results
        }

        node.size = bytes
        node.fileCount = count
        for child in children {
            node.size += child.node.size
            node.fileCount += child.node.fileCount
            largest.merge(child.largest)
            if dups.count < ctx.options.duplicateCandidateCap { dups.append(contentsOf: child.dupCandidates) }
            unreadable += child.unreadable
        }
        node.unreadable = unreadable
        if level < ctx.options.storeDepth {
            node.children = children.map(\.node).sorted { $0.size > $1.size }
        } else {
            node.isComplete = children.isEmpty
        }
        // directFiles'ın dışında kalanlar insert sırasında "diğer"e eklendi; ama listeye girip
        // sonradan daha büyükleri tarafından itilenler de "diğer"e eklenmeli:
        node.files = directFiles.items.sortedDescending()
        node.otherFilesSize += directFiles.evictedSize
        node.otherFilesCount += directFiles.evictedCount
        return Partial(node: node, largest: largest, dupCandidates: dups, unreadable: unreadable)
    }

    /// Bir alt ağacı tek iş parçacığında `fts` ile tarar.
    private static func ftsUnit(_ rootPath: String, baseLevel: Int, top: String?,
                                ctx: Context) -> Partial {
        let opts = ctx.options
        var largest = TopFiles(limit: opts.largestLimit)
        var dups: [FileEntry] = []
        var unreadable = 0
        var seenInodes = Set<InodeKey>()

        // Düğüm yığını: yalnızca saklanan düzeylerdeki klasörler için.
        final class Frame {
            let node: DirNode
            var files: TopFiles
            var subdirs: [DirNode] = []
            var truncated = false
            init(node: DirNode, limit: Int) { self.node = node; self.files = TopFiles(limit: limit) }
        }
        var stack: [Frame] = []
        var rootNode: DirNode?

        var pendingFiles = 0
        var pendingBytes: Int64 = 0
        var tick = 0

        guard let cPath = strdup(rootPath) else {
            let node = DirNode(path: rootPath, level: baseLevel)
            node.unreadable = 1
            return Partial(node: node, largest: largest, dupCandidates: [], unreadable: 1)
        }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else {
            let node = DirNode(path: rootPath, level: baseLevel)
            node.unreadable = 1
            return Partial(node: node, largest: largest, dupCandidates: [], unreadable: 1)
        }
        defer { fts_close(fts) }

        func finish(_ frame: Frame) {
            let n = frame.node
            n.files = frame.files.items.sortedDescending()
            n.otherFilesSize += frame.files.evictedSize
            n.otherFilesCount += frame.files.evictedCount
            n.children = frame.subdirs.sorted { $0.size > $1.size }
            if frame.truncated { n.isComplete = false }
            if let parent = stack.last {
                parent.node.size += n.size
                parent.node.fileCount += n.fileCount
                parent.node.unreadable += n.unreadable
                parent.subdirs.append(n)
            } else {
                rootNode = n
            }
        }

        while let ent = fts_read(fts) {
            tick += 1
            if tick & 0x3FF == 0 {
                if Task.isCancelled { break }
                ctx.progress?.add(files: pendingFiles, bytes: pendingBytes, top: top,
                                  current: String(cString: ent.pointee.fts_path))
                pendingFiles = 0; pendingBytes = 0
            }

            let info = Int32(ent.pointee.fts_info)
            let level = baseLevel + Int(ent.pointee.fts_level)
            let isRootEntry = ent.pointee.fts_level == 0

            switch info {
            case FTS_D:
                if !opts.includeHidden && !isRootEntry && isHiddenName(ent) {
                    fts_set(fts, ent, FTS_SKIP)
                    continue
                }
                let size = Int64(ent.pointee.fts_statp.pointee.st_blocks) * 512
                pendingBytes += size
                if level <= opts.storeDepth {
                    let node = DirNode(path: String(cString: ent.pointee.fts_path), level: level)
                    node.size = size
                    stack.append(Frame(node: node, limit: opts.filesPerNode))
                } else if let frame = stack.last {
                    frame.node.size += size
                    frame.truncated = true
                }

            case FTS_DP, FTS_DNR, FTS_ERR:
                if info != FTS_DP {
                    unreadable += 1
                    if let frame = stack.last { frame.node.unreadable += 1 }
                }
                if level <= opts.storeDepth, let frame = stack.last, frame.node.level == level,
                   info == FTS_DP || frame.node.path == String(cString: ent.pointee.fts_path) {
                    stack.removeLast()
                    finish(frame)
                }

            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                if !opts.includeHidden && isHiddenName(ent) { continue }
                let st = ent.pointee.fts_statp.pointee
                // Sabit bağlantılar (hard link) yalnızca bir kez sayılsın.
                if info == FTS_F && st.st_nlink > 1 {
                    if !seenInodes.insert(InodeKey(dev: st.st_dev, ino: st.st_ino)).inserted { continue }
                }
                let size = Int64(st.st_blocks) * 512
                pendingFiles += 1
                pendingBytes += size
                guard let frame = stack.last else { continue }
                frame.node.size += size
                frame.node.fileCount += 1

                if info == FTS_F {
                    let file = FileEntry(path: String(cString: ent.pointee.fts_path),
                                         size: size, logicalSize: Int64(st.st_size))
                    largest.insert(file)
                    if Int64(st.st_size) >= opts.duplicateMinSize && dups.count < opts.duplicateCandidateCap {
                        dups.append(file)
                    }
                    if frame.node.level == level - 1 {
                        if !frame.files.insert(file) {
                            frame.node.otherFilesSize += size
                            frame.node.otherFilesCount += 1
                        }
                    }
                } else if frame.node.level == level - 1 {
                    frame.node.otherFilesSize += size
                    frame.node.otherFilesCount += 1
                }

            case FTS_NS:
                unreadable += 1

            default:
                break   // FTS_DC (döngü), FTS_DOT vb.
            }
        }

        // İptal ya da beklenmedik çıkışta açık kalan çerçeveleri kapat.
        while let frame = stack.popLast() { finish(frame) }
        ctx.progress?.add(files: pendingFiles, bytes: pendingBytes, top: top, current: nil)

        let node = rootNode ?? DirNode(path: rootPath, level: baseLevel)
        return Partial(node: node, largest: largest, dupCandidates: dups, unreadable: unreadable)
    }

    private static func isHiddenName(_ ent: UnsafeMutablePointer<FTSENT>) -> Bool {
        // fts_name esnek dizi; ilk karakteri yeterli.
        withUnsafePointer(to: &ent.pointee.fts_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { $0.pointee == 0x2E }
        }
    }

    /// `opendir/readdir/lstat` ile tek klasörü listeler (gizliler dahil). Okunamazsa nil.
    private static func listDirectory(_ path: String) -> [(name: String, stat: stat)]? {
        guard let dir = opendir(path) else { return nil }
        defer { closedir(dir) }
        var result: [(name: String, stat: stat)] = []
        while let ent = readdir(dir) {
            let name = withUnsafePointer(to: &ent.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            let full = path == "/" ? "/" + name : path + "/" + name
            var st = stat()
            guard lstat(full, &st) == 0 else { continue }
            result.append((name, st))
        }
        return result
    }
}

private struct InodeKey: Hashable {
    let dev: dev_t
    let ino: ino_t
}

// MARK: - En büyük N dosya

/// Boyuta göre en büyük `limit` dosyayı tutan, artan sıralı küçük kap.
struct TopFiles: Sendable {
    let limit: Int
    private(set) var items: [FileEntry] = []   // artan (en küçük başta)
    private(set) var evictedSize: Int64 = 0
    private(set) var evictedCount = 0

    init(limit: Int) { self.limit = limit }

    /// Eklendiyse `true`; sığmadıysa `false` döner. Dışarı itilen öğe `evicted*`'a yazılır.
    @discardableResult
    mutating func insert(_ file: FileEntry) -> Bool {
        guard limit > 0 else { return false }
        if items.count >= limit {
            guard let smallest = items.first, file.size > smallest.size else { return false }
            items.removeFirst()
            evictedSize += smallest.size
            evictedCount += 1
        }
        var lo = 0, hi = items.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if items[mid].size < file.size { lo = mid + 1 } else { hi = mid }
        }
        items.insert(file, at: lo)
        return true
    }

    mutating func merge(_ other: TopFiles) {
        for f in other.items { insert(f) }
    }

    func sortedDescending() -> [FileEntry] { items.reversed() }
}

private extension Array where Element == FileEntry {
    func sortedDescending() -> [FileEntry] { sorted { $0.size > $1.size } }
}
