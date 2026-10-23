import SwiftUI
import AppKit

enum DiskMode: String, CaseIterable, Identifiable {
    case folders = "Klasörler"
    case largest = "En Büyük Dosyalar"
    case duplicates = "Yinelenenler"
    var id: String { rawValue }
}

/// Çöpe taşıma onayı bekleyen öğe.
private struct PendingTrash: Identifiable {
    let path: String
    let size: Int64
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

struct DiskView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @ObservedObject var store: DiskScanStore

    @State private var mode: DiskMode = .folders
    @State private var pendingTrash: PendingTrash?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            statusStrip
            Divider()
            content
        }
        .navigationTitle("Disk Analizi")
        .onAppear { if store.phase == .idle { store.scan() } }
        .confirmationDialog(
            "“\(pendingTrash?.name ?? "")” çöpe taşınsın mı?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            titleVisibility: .visible,
            presenting: pendingTrash
        ) { item in
            Button("Çöpe Taşı (\(Fmt.bytes(item.size)))", role: .destructive) {
                store.trash(path: item.path, size: item.size)
            }
            Button("Vazgeç", role: .cancel) { }
        } message: { item in
            Text("\(item.path)\n\nÖğe Çöp Kutusu'na taşınır; geri alınabilir. Yer, çöp boşaltılınca açılır.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .folders:    foldersContent
        case .largest:    largestContent
        case .duplicates: duplicatesContent
        }
    }

    // MARK: - Araç çubuğu

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                Button { store.scan(FileManager.default.homeDirectoryForCurrentUser) } label: {
                    Label("Ev Klasörü", systemImage: "house")
                }
                Button { store.scan(URL(fileURLWithPath: "/System/Volumes/Data")) } label: {
                    Label("Tüm Disk (Veri birimi)", systemImage: "internaldrive")
                }
                Button { store.scan(URL(fileURLWithPath: "/Applications")) } label: {
                    Label("Uygulamalar", systemImage: "app.dashed")
                }
                Divider()
                Button { chooseFolder() } label: {
                    Label("Klasör Seç…", systemImage: "folder.badge.plus")
                }
            } label: {
                Label(locationName, systemImage: "scope")
            }
            .fixedSize()
            .help("Taranacak konum")

            if store.phase == .scanning {
                Button(role: .cancel) { store.cancel() } label: {
                    Label("Durdur", systemImage: "stop.fill")
                }
            } else {
                Button { store.scan() } label: {
                    Label("Yeniden Tara", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            Toggle("Gizli dosyalar", isOn: $store.includeHidden)
                .toggleStyle(.checkbox)
                .help("~/.nuget, ~/.npm gibi gizli klasörler genellikle çok yer kaplar. Değişiklik bir sonraki taramada uygulanır.")

            Spacer()

            Picker("", selection: $mode) {
                ForEach(DiskMode.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(10)
        .background(Theme.surface)
    }

    private var locationName: String {
        let path = store.rootURL.path
        if path == FileManager.default.homeDirectoryForCurrentUser.path { return String(localized: "Ev Klasörü") }
        if path == "/System/Volumes/Data" { return String(localized: "Tüm Disk") }
        return store.rootURL.lastPathComponent
    }

    // MARK: - Durum şeridi

    @ViewBuilder
    private var statusStrip: some View {
        HStack(spacing: 10) {
            switch store.phase {
            case .scanning:
                ProgressView().controlSize(.small)
                Text("\(store.live.files.formatted()) dosya · \(Fmt.bytes(store.live.bytes)) tarandı")
                    .monospacedDigit()
                Text(store.live.current)
                    .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(store.fileCount.formatted()) dosya · \(String(format: "%.1f", store.duration)) sn")
                    .monospacedDigit()
                if let finished = store.finishedAt {
                    Text("· \(finished, format: .relative(presentation: .named))").foregroundStyle(.secondary)
                }
                if store.unreadable > 0 {
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("\(store.unreadable) klasöre erişilemedi — Tüm Diske Erişim ver", systemImage: "lock")
                    }
                    .buttonStyle(.link)
                    .help("Sistem Ayarları → Gizlilik ve Güvenlik → Tüm Diske Erişim → VitalMac")
                }
            case .cancelled:
                Image(systemName: "stop.circle").foregroundStyle(.orange)
                Text("Tarama durduruldu.")
            case .idle:
                Text("Hazır.")
            }
            Spacer()
            diskCapacity
        }
        .font(.caption)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    /// Birimin doluluk özeti (sağ üst).
    private var diskCapacity: some View {
        let d = monitor.disk
        return HStack(spacing: 6) {
            ProgressView(value: min(max(d.usedPercent / 100, 0), 1))
                .tint(Fmt.color(for: d.usedPercent))
                .frame(width: 80)
            Text("\(Fmt.bytes(d.free)) boş / \(Fmt.bytes(d.total))")
                .monospacedDigit().foregroundStyle(.secondary)
        }
    }

    // MARK: - Klasörler

    @ViewBuilder
    private var foldersContent: some View {
        if let node = store.current {
            VStack(spacing: 0) {
                breadcrumb
                ScrollView {
                    VStack(spacing: 16) {
                        messageBanner
                        let entries = node.entries
                        if entries.isEmpty {
                            emptyHint
                        } else {
                            Card(title: "Disk Haritası — \(node.name)", systemImage: "square.grid.3x3.fill") {
                                TreemapView(entries: Array(entries.prefix(60))) { open($0) }
                                    .frame(height: 300)
                            }
                            Card(title: "İçerik (\(Fmt.bytes(node.size)))", systemImage: "list.bullet") {
                                LazyVStack(spacing: 6) {
                                    ForEach(entries.prefix(200)) { entry in
                                        entryRow(entry, total: node.size)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .overlay {
                if let sub = store.subScanPath {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("“\((sub as NSString).lastPathComponent)” ayrıntılı taranıyor…").font(.caption)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        } else if store.phase == .scanning {
            liveProgress
        } else {
            emptyHint
        }
    }

    /// Tarama sürerken birinci düzey klasörlerin canlı büyüyen boyutları.
    private var liveProgress: some View {
        let tops = store.live.topSizes.sorted { $0.value > $1.value }
        let maxSize = max(tops.first?.value ?? 1, 1)
        return ScrollView {
            Card(title: "Taranıyor — en büyükler şimdiden görünüyor", systemImage: "hourglass") {
                if tops.isEmpty {
                    Text("Klasörler listeleniyor…").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(tops.prefix(25), id: \.key) { name, size in
                    ProportionRow(title: name, detail: Fmt.bytes(size),
                                  fraction: Double(size) / Double(maxSize), color: .blue)
                }
            }
            .padding(20)
        }
        .animation(.easeOut(duration: 0.25), value: store.live.bytes)
    }

    private func entryRow(_ entry: DiskEntry, total: Int64) -> some View {
        let isFolder: Bool = { if case .folder = entry { return true }; return false }()
        let isOther: Bool = { if case .others = entry { return true }; return false }()
        let fraction = total > 0 ? Double(entry.size) / Double(total) : 0
        return Button { open(entry) } label: {
            HStack(spacing: 8) {
                Image(systemName: isFolder ? "folder.fill" : isOther ? "ellipsis.circle" : "doc")
                    .foregroundStyle(isFolder ? .blue : .secondary)
                    .frame(width: 16)
                ProportionRow(
                    title: entry.name,
                    detail: String(localized: "\(Fmt.bytes(entry.size)) · \(Fmt.percent1(fraction * 100))"),
                    fraction: fraction,
                    color: isFolder ? .blue : isOther ? .gray : .teal
                )
                Image(systemName: "chevron.right").font(.caption2)
                    .foregroundStyle(.tertiary)
                    .opacity(isFolder ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOther)
        .contextMenu { if let path = entry.path { itemMenu(path: path, size: entry.size) } }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(store.stack.enumerated()), id: \.element.id) { index, node in
                    Button(index == 0 ? node.path : node.name) { store.pop(to: index) }
                        .buttonStyle(.link)
                        .disabled(index == store.stack.count - 1)
                    if index < store.stack.count - 1 {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(Theme.inset)
    }

    // MARK: - En büyük dosyalar

    @ViewBuilder
    private var largestContent: some View {
        if store.phase == .scanning && store.largest.isEmpty {
            waiting(String(localized: "En büyük dosyalar tarama bitince listelenir…"))
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    messageBanner
                    Card(title: "En büyük dosyalar — \(locationName)", systemImage: "arrow.down.circle") {
                        if store.largest.isEmpty {
                            Text("Sonuç yok.").foregroundStyle(.secondary)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(store.largest.prefix(150)) { file in
                                    fileRow(file)
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func fileRow(_ file: FileEntry) -> some View {
        Button { reveal(file.path) } label: {
            HStack {
                Image(systemName: "doc.fill").foregroundStyle(.secondary).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name).lineLimit(1)
                    Text(SpaceSaver.tilde((file.path as NSString).deletingLastPathComponent))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(Fmt.bytes(file.size)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { itemMenu(path: file.path, size: file.size) }
    }

    // MARK: - Yinelenenler

    @ViewBuilder
    private var duplicatesContent: some View {
        if store.phase == .scanning {
            waiting(String(localized: "Yinelenenler, tarama bittikten sonra aranabilir…"))
        } else if store.dupPhase == .scanning {
            waiting(String(localized: "İçerik örnekleri karşılaştırılıyor…"))
        } else if store.dupPhase == .idle {
            VStack(spacing: 12) {
                Image(systemName: "doc.on.doc").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("1 MB üstü aynı boyutlu dosyaların içeriği karşılaştırılır.")
                    .foregroundStyle(.secondary)
                Button { store.findDuplicates() } label: {
                    Label("Yinelenenleri Bul", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.phase != .done)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    messageBanner
                    if store.duplicates.isEmpty {
                        Text("Yinelenen dosya bulunamadı.").foregroundStyle(.secondary).padding(40)
                    } else {
                        let wasted = store.duplicates.reduce(0) { $0 + $1.wasted }
                        Label("Olası \(store.duplicates.count) yinelenen grup · \(Fmt.bytes(wasted)) gereksiz yer",
                              systemImage: "doc.on.doc")
                            .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        Text("Not: APFS klonları (Finder'da kopyalanmış dosyalar) aynı blokları paylaşabilir; silmek beklenen yeri açmayabilir.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LazyVStack(spacing: 12) {
                            ForEach(store.duplicates.prefix(80)) { group in
                                DuplicateGroupCard(group: group, reveal: reveal) { file in
                                    if store.canTrash(file.path) {
                                        pendingTrash = PendingTrash(path: file.path, size: file.size)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Ortak parçalar

    @ViewBuilder
    private func itemMenu(path: String, size: Int64) -> some View {
        Button("Finder'da Göster") { reveal(path) }
        Button("Yolu Kopyala") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
        Divider()
        Button("Çöpe Taşı…", role: .destructive) {
            pendingTrash = PendingTrash(path: path, size: size)
        }
        .disabled(!store.canTrash(path))
    }

    @ViewBuilder
    private var messageBanner: some View {
        if let message = store.message {
            HStack {
                Label(message, systemImage: "info.circle").font(.callout)
                Spacer()
                Button { store.message = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func waiting(_ text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "internaldrive").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Bu konumda gösterilecek bir şey bulunamadı").foregroundStyle(.secondary)
            Text("Tüm diski taramak için Sistem Ayarları → Gizlilik → Tüm Diske Erişim'den izin verin.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    // MARK: - Eylemler

    private func open(_ entry: DiskEntry) {
        switch entry {
        case .folder(let node): store.open(node)
        case .file(let file):   reveal(file.path)
        case .others:           break
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { store.scan(url) }
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// Yinelenen grup kartı.
private struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let reveal: (String) -> Void
    let trash: (FileEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.files.first?.name ?? String(localized: "Dosya")).font(.headline).lineLimit(1)
                Spacer()
                Text("\(group.files.count)× · \(Fmt.bytes(group.fileSize))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            ForEach(group.files) { file in
                HStack {
                    Image(systemName: "doc").font(.caption2).foregroundStyle(.secondary)
                    Button { reveal(file.path) } label: {
                        Text(SpaceSaver.tilde(file.path)).font(.caption).lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { trash(file) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .disabled(!SafeTrash.isAllowed(file.path))
                        .help("Bu kopyayı çöpe taşı")
                }
            }
            Text("Gereksiz: \(Fmt.bytes(group.wasted))")
                .font(.caption2).foregroundStyle(.orange)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Basit ikili-bölme (squarish) treemap görünümü; üzerine gelince vurgular.
struct TreemapView: View {
    var entries: [DiskEntry]
    var onTap: (DiskEntry) -> Void

    @State private var hovered: String?
    private let palette: [Color] = [Theme.disk, Theme.cpu, Theme.memory, Theme.gpu, Theme.network, Theme.heat]

    var body: some View {
        GeometryReader { geo in
            let rects = Treemap.layout(entries, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(rects.enumerated()), id: \.element.entry.id) { index, tr in
                    let color: Color = {
                        switch tr.entry {
                        case .folder: return palette[index % palette.count]
                        case .file:   return .gray
                        case .others: return Color.secondary.opacity(0.5)
                        }
                    }()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.gradient)
                        .brightness(hovered == tr.entry.id ? 0.12 : 0)
                        .overlay(
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tr.entry.name).font(.caption2.bold()).lineLimit(1)
                                Text(Fmt.bytes(tr.entry.size)).font(.caption2)
                            }
                            .padding(4)
                            .foregroundStyle(.white)
                            .opacity(tr.rect.width > 64 && tr.rect.height > 30 ? 1 : 0),
                            alignment: .topLeading
                        )
                        .frame(width: max(tr.rect.width - 2, 0), height: max(tr.rect.height - 2, 0))
                        .offset(x: tr.rect.minX, y: tr.rect.minY)
                        .onTapGesture { onTap(tr.entry) }
                        .onHover { inside in hovered = inside ? tr.entry.id : (hovered == tr.entry.id ? nil : hovered) }
                        .help("\(tr.entry.name) — \(Fmt.bytes(tr.entry.size))")
                }
            }
        }
    }
}

/// Treemap yerleşim hesabı (ikili bölme algoritması).
enum Treemap {
    struct Placed { let entry: DiskEntry; let rect: CGRect }

    static func layout(_ entries: [DiskEntry], in rect: CGRect) -> [Placed] {
        let positive = entries.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        guard !positive.isEmpty else { return [] }
        return split(positive, rect)
    }

    private static func split(_ items: [DiskEntry], _ rect: CGRect) -> [Placed] {
        if items.count == 1 { return [Placed(entry: items[0], rect: rect)] }
        let total = items.reduce(0.0) { $0 + Double($1.size) }
        guard total > 0 else { return [] }

        var accumulated = 0.0
        var splitIndex = 0
        for (index, item) in items.enumerated() {
            accumulated += Double(item.size)
            splitIndex = index + 1
            if accumulated >= total / 2 { break }
        }
        splitIndex = min(max(splitIndex, 1), items.count - 1)

        let first = Array(items[..<splitIndex])
        let second = Array(items[splitIndex...])
        let firstFraction = first.reduce(0.0) { $0 + Double($1.size) } / total

        var r1 = rect, r2 = rect
        if rect.width >= rect.height {
            r1.size.width = rect.width * firstFraction
            r2.origin.x = rect.minX + r1.size.width
            r2.size.width = rect.width - r1.size.width
        } else {
            r1.size.height = rect.height * firstFraction
            r2.origin.y = rect.minY + r1.size.height
            r2.size.height = rect.height - r1.size.height
        }
        return split(first, r1) + split(second, r2)
    }
}
