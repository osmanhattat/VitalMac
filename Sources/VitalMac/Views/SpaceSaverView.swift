import SwiftUI
import AppKit

/// "Alan Kazan": geliştirici önbellekleri, proje derleme çıktıları, simülatör runtime'ları,
/// aerial duvar kağıtları ve eski indirmeler gibi geri kazanılabilir alanları tek listede gösterir.
struct SpaceSaverView: View {
    @ObservedObject var store: SpaceSaverStore
    @State private var confirmTrash = false
    @State private var confirmEmptyTrash = false
    @State private var pendingCommand: JunkItem?
    @State private var collapsed: Set<JunkItem.Group> = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if store.scanning && store.items.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Önbellekler, proje çıktıları ve simülatörler ölçülüyor…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal").font(.system(size: 44)).foregroundStyle(.green)
                    Text(store.scannedAt == nil ? "Taramak için Yeniden Tara'ya basın." : "Kayda değer gereksiz alan bulunamadı.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        summary
                        if let message = store.message { banner(message) }
                        ForEach(JunkItem.Group.allCases, id: \.self) { group in
                            let items = store.items.filter { $0.group == group }
                            if !items.isEmpty { groupCard(group, items) }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Alan Kazan")
        .onAppear { if store.scannedAt == nil && !store.scanning { store.scan() } }
        .confirmationDialog(
            "\(store.selectedItems.count) öğe çöpe taşınsın mı? (\(Fmt.bytes(store.selectedSize)))",
            isPresented: $confirmTrash, titleVisibility: .visible
        ) {
            Button("Çöpe Taşı", role: .destructive) { store.trashSelected() }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Öğeler Çöp Kutusu'na taşınır, geri alınabilir. Disk alanı Çöp Kutusu boşaltılınca açılır.")
        }
        .confirmationDialog(
            "Çöp Kutusu kalıcı olarak boşaltılsın mı?",
            isPresented: $confirmEmptyTrash, titleVisibility: .visible
        ) {
            Button("Çöpü Boşalt", role: .destructive) { store.emptyTrash() }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Bu işlem geri alınamaz.")
        }
        .confirmationDialog(
            "\(pendingCommand?.title ?? "") kaldırılsın mı?",
            isPresented: Binding(get: { pendingCommand != nil }, set: { if !$0 { pendingCommand = nil } }),
            titleVisibility: .visible, presenting: pendingCommand
        ) { item in
            Button("Kaldır (\(Fmt.bytes(item.size)))", role: .destructive) { store.runCommand(item) }
            Button("Vazgeç", role: .cancel) { }
        } message: { item in
            Text(item.note + String(localized: "\n\nBu işlem Çöp Kutusu'na gitmez, doğrudan kaldırılır."))
        }
    }

    // MARK: Parçalar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { store.scan() } label: { Label("Yeniden Tara", systemImage: "arrow.clockwise") }
                .disabled(store.scanning)
            Button { chooseProjectRoot() } label: { Label("Proje Klasörü Ekle…", systemImage: "folder.badge.plus") }
                .help(String(localized: "Proje derleme çıktılarının (node_modules, bin/obj, build…) aranacağı klasörler:\n")
                      + store.projectRoots.map(SpaceSaver.tilde).joined(separator: "\n"))
            if store.scanning || store.working { ProgressView().controlSize(.small) }
            Spacer()
            Text("Seçili: \(Fmt.bytes(store.selectedSize))")
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            Button { confirmEmptyTrash = true } label: { Label("Çöpü Boşalt", systemImage: "trash.slash") }
                .disabled(store.working)
            Button { confirmTrash = true } label: { Label("Seçilenleri Çöpe Taşı", systemImage: "trash") }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedSize == 0 || store.working)
        }
        .padding(10)
        .background(Theme.surface)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            StatBadge(label: "Bulunan toplam", value: Fmt.bytes(store.totalSize), color: .orange)
            StatBadge(label: "Güvenle silinebilir", value: Fmt.bytes(store.safeSize), color: .green)
            StatBadge(label: "Kalem", value: "\(store.items.count)")
        }
    }

    private func banner(_ text: String) -> some View {
        HStack(alignment: .top) {
            Label(text, systemImage: "info.circle").font(.callout)
            Spacer()
            Button { store.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func groupCard(_ group: JunkItem.Group, _ items: [JunkItem]) -> some View {
        let total = items.reduce(0) { $0 + $1.size }
        let isOpen = !collapsed.contains(group)
        let trashable = items.filter { if case .trash = $0.action { return true }; return false }
        let allSelected = !trashable.isEmpty && trashable.allSatisfy { store.selected.contains($0.id) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isOpen { collapsed.insert(group) } else { collapsed.remove(group) }
                    }
                } label: {
                    HStack {
                        Image(systemName: group.icon).foregroundStyle(.tint).frame(width: 20)
                        Text(LocalizedStringKey(group.rawValue)).font(.headline)
                        Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if !trashable.isEmpty {
                    Button(allSelected ? "Hiçbiri" : "Tümü") {
                        let ids = trashable.map(\.id)
                        if allSelected { store.selected.subtract(ids) } else { store.selected.formUnion(ids) }
                    }
                    .buttonStyle(.link).font(.caption)
                }
                Text(Fmt.bytes(total)).font(.headline).monospacedDigit()
            }
            if isOpen {
                // Tüm kalemler listelenir: seçili olup görünmeyen kalem olmamalı.
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        Divider()
                        row(item)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(14)
        .cardSurface(cornerRadius: 14)
    }

    private func row(_ item: JunkItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            switch item.action {
            case .trash:
                Toggle("", isOn: Binding(
                    get: { store.selected.contains(item.id) },
                    set: { on in if on { store.selected.insert(item.id) } else { store.selected.remove(item.id) } }
                ))
                .labelsHidden()
            case .command:
                Image(systemName: "terminal").foregroundStyle(.secondary).frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(item.safety.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background((item.safety == .safe ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                        .foregroundStyle(item.safety == .safe ? .green : .orange)
                }
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text(item.note).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.bytes(item.size)).font(.callout).monospacedDigit()
                if let date = item.lastUsed {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                HStack(spacing: 6) {
                    if let path = item.revealPath {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless).help("Finder'da göster")
                    }
                    if case .command = item.action {
                        Button("Kaldır…") { pendingCommand = item }
                            .controlSize(.small)
                            .disabled(store.working)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func chooseProjectRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Ekle")
        if panel.runModal() == .OK, let url = panel.url { store.addProjectRoot(url.path) }
    }
}
