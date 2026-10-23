import Foundation
import SwiftUI

/// Disk Analizi sayfasının durumu. RootView'da tek örnek yaşar; böylece sayfadan çıkıp
/// geri dönünce tarama baştan başlamaz, sonuç anında görünür.
@MainActor
final class DiskScanStore: ObservableObject {

    enum Phase: Equatable { case idle, scanning, done, cancelled }
    enum DupPhase: Equatable { case idle, scanning, done }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var rootURL = FileManager.default.homeDirectoryForCurrentUser
    @Published private(set) var stack: [DirNode] = []
    @Published private(set) var largest: [FileEntry] = []
    @Published private(set) var duplicates: [DuplicateGroup] = []
    @Published private(set) var dupPhase: DupPhase = .idle
    @Published private(set) var live = ScanProgress.Snapshot()
    @Published private(set) var fileCount = 0
    @Published private(set) var unreadable = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var finishedAt: Date?
    /// Derinlik sınırındaki bir klasöre inilirken yapılan alt taramanın yolu.
    @Published private(set) var subScanPath: String?
    @Published var message: String?

    @Published var includeHidden: Bool = UserDefaults.standard.object(forKey: "disk.includeHidden") as? Bool ?? true {
        didSet { UserDefaults.standard.set(includeHidden, forKey: "disk.includeHidden") }
    }

    var current: DirNode? { stack.last }
    var root: DirNode? { stack.first }

    private var scanTask: Task<ScanResult, Never>?
    private var dupTask: Task<Void, Never>?
    private var subTask: Task<Void, Never>?
    private var dupCandidates: [FileEntry] = []
    private var generation = 0

    // MARK: Tarama

    func scan(_ url: URL? = nil) {
        if let url { rootURL = url }
        cancelAll()
        generation += 1
        let gen = generation
        let target = rootURL
        var options = DiskScanner.Options()
        options.includeHidden = includeHidden

        phase = .scanning
        stack = []
        largest = []
        duplicates = []
        dupPhase = .idle
        dupCandidates = []
        message = nil
        live = .init()

        let progress = ScanProgress()
        let task = Task.detached(priority: .userInitiated) {
            await DiskScanner.scan(target, options: options, progress: progress)
        }
        scanTask = task

        // Canlı ilerleme: ana iş parçacığını boğmadan 4 Hz okur.
        Task { [weak self] in
            while let self, self.generation == gen, self.phase == .scanning {
                self.live = progress.snapshot
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        Task { [weak self] in
            let result = await task.value
            guard let self, self.generation == gen else { return }
            if task.isCancelled {
                self.phase = .cancelled
                return
            }
            self.stack = [result.root]
            self.largest = result.largest
            self.dupCandidates = result.duplicateCandidates
            self.fileCount = result.fileCount
            self.unreadable = result.unreadable
            self.duration = result.duration
            self.finishedAt = Date()
            self.live = progress.snapshot
            self.phase = .done
        }
    }

    func cancel() {
        guard phase == .scanning else { return }
        cancelAll()
        generation += 1
        phase = stack.isEmpty ? .cancelled : .done
    }

    private func cancelAll() {
        scanTask?.cancel(); scanTask = nil
        dupTask?.cancel(); dupTask = nil
        subTask?.cancel(); subTask = nil
        subScanPath = nil
    }

    // MARK: Gezinme

    func open(_ node: DirNode) {
        guard subScanPath == nil else { return }
        if node.isComplete {
            stack.append(node)
            return
        }
        // Derinlik sınırı: yalnızca bu alt ağacı tara, sonra düğümün yerine koy.
        subScanPath = node.path
        let gen = generation
        var options = DiskScanner.Options()
        options.includeHidden = includeHidden
        options.largestLimit = 0
        options.duplicateMinSize = .max
        let url = node.url
        subTask = Task { [weak self] in
            let inner = Task.detached(priority: .userInitiated) {
                await DiskScanner.scan(url, options: options, progress: ScanProgress())
            }
            let result = await withTaskCancellationHandler {
                await inner.value
            } onCancel: {
                inner.cancel()
            }
            guard let self, self.generation == gen, !Task.isCancelled else { return }
            node.adopt(result.root)
            node.isComplete = true
            self.subScanPath = nil
            self.stack.append(node)
        }
    }

    func pop(to index: Int) {
        guard index >= 0, index < stack.count else { return }
        stack = Array(stack.prefix(index + 1))
    }

    // MARK: Yinelenenler

    func findDuplicates() {
        guard dupPhase != .scanning, !dupCandidates.isEmpty else {
            if dupCandidates.isEmpty { dupPhase = .done }
            return
        }
        dupPhase = .scanning
        let candidates = dupCandidates
        let gen = generation
        dupTask = Task { [weak self] in
            let inner = Task.detached(priority: .userInitiated) { await DuplicateFinder.find(candidates) }
            let groups = await withTaskCancellationHandler { await inner.value } onCancel: { inner.cancel() }
            guard let self, self.generation == gen, !Task.isCancelled else { return }
            self.duplicates = groups
            self.dupPhase = .done
        }
    }

    // MARK: Çöpe taşıma

    /// Silinen öğeyi ağaçtan çıkarır ve kökten öğeye kadar tüm ataların boyutunu düşer.
    private static func remove(path: String, size: Int64, from root: DirNode) {
        func isAncestor(_ dir: String) -> Bool {
            dir == "/" ? path.hasPrefix("/") : path.hasPrefix(dir + "/")
        }
        var node = root
        guard isAncestor(node.path) else { return }
        while true {
            node.size = max(0, node.size - size)
            if let i = node.children.firstIndex(where: { $0.path == path }) {
                node.children.remove(at: i)
                return
            }
            if let i = node.files.firstIndex(where: { $0.path == path }) {
                node.files.remove(at: i)
                return
            }
            guard let next = node.children.first(where: { isAncestor($0.path) }) else {
                // Öğe saklanmayan derinlikte ya da "küçük dosyalar" içinde.
                if (path as NSString).deletingLastPathComponent == node.path {
                    node.otherFilesSize = max(0, node.otherFilesSize - size)
                }
                return
            }
            node = next
        }
    }

    func canTrash(_ path: String) -> Bool { SafeTrash.isAllowed(path) }

    /// Öğeyi çöpe taşır ve ağaçtaki boyutları yerinde günceller (yeniden tarama gerekmez).
    func trash(path: String, size: Int64) {
        do {
            try SafeTrash.trash(path)
        } catch {
            message = error.localizedDescription
            return
        }
        if let root { Self.remove(path: path, size: size, from: root) }
        largest.removeAll { $0.path == path || $0.path.hasPrefix(path + "/") }
        dupCandidates.removeAll { $0.path == path || $0.path.hasPrefix(path + "/") }
        duplicates = duplicates.compactMap { group in
            var g = group
            g.files.removeAll { $0.path == path || $0.path.hasPrefix(path + "/") }
            return g.files.count > 1 ? g : nil
        }
        message = String(localized: "\((path as NSString).lastPathComponent) çöpe taşındı (\(Fmt.bytes(size))). Yer, Çöp Kutusu boşaltılınca açılır.")
        objectWillChange.send()
    }
}
