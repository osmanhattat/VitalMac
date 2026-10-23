import SwiftUI

struct UninstallerView: View {
    @ObservedObject var uninstaller: AppUninstaller

    @State private var selected: InstalledApp?
    @State private var relatedFiles: [URL] = []
    @State private var excluded = Set<URL>()      // kullanıcının işaretini kaldırdığı öğeler
    @State private var showSheet = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var search = ""

    private var filteredApps: [InstalledApp] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return uninstaller.apps }
        return uninstaller.apps.filter {
            $0.name.localizedCaseInsensitiveContains(q) || ($0.bundleId?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if uninstaller.scanning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Uygulamalar taranıyor…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "app.dashed").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text(search.isEmpty ? "Uygulama bulunamadı" : "“\(search)” ile eşleşen uygulama yok")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20).padding(.top, 12)
                            .textSelection(.enabled)
                    }
                    LazyVStack(spacing: 8) {
                        ForEach(filteredApps) { app in
                            HStack(spacing: 12) {
                                if let icon = app.icon {
                                    Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name).font(.headline)
                                    Text(app.bundleId ?? app.url.lastPathComponent)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(Fmt.bytes(app.size)).monospacedDigit().foregroundStyle(.secondary)
                                Button {
                                    prepareUninstall(app)
                                } label: {
                                    Label("Kaldır", systemImage: "trash")
                                }
                                .disabled(uninstaller.protectionReason(for: app) != nil)
                                .help(uninstaller.protectionReason(for: app) ?? "Uygulamayı ve artık dosyalarını çöpe taşı")
                            }
                            .padding(12)
                            .cardSurface(cornerRadius: 12)
                            .contextMenu {
                                Button("Finder'da Göster") {
                                    NSWorkspace.shared.activateFileViewerSelecting([app.url])
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Uygulamalar")
        .onAppear { if uninstaller.apps.isEmpty { uninstaller.scan() } }
        .sheet(isPresented: $showSheet) { uninstallSheet }
    }

    private var toolbar: some View {
        HStack {
            Button { uninstaller.scan() } label: {
                Label("Yeniden Tara", systemImage: "arrow.clockwise")
            }
            TextField("Ara…", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Spacer()
            Text("\(uninstaller.apps.count) uygulama · \(Fmt.bytes(uninstaller.apps.reduce(0) { $0 + $1.size }))")
                .font(.caption).foregroundStyle(.secondary)
            if let resultMessage {
                Text(resultMessage).font(.caption).foregroundStyle(.green)
            }
        }
        .padding(10)
        .background(Theme.surface)
    }

    @ViewBuilder
    private var uninstallSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let app = selected {
                HStack(spacing: 10) {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 40, height: 40)
                    }
                    VStack(alignment: .leading) {
                        Text("“\(app.name)” kaldırılsın mı?").font(.headline)
                        Text("Aşağıdaki öğeler çöp kutusuna taşınacak (geri alınabilir).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(relatedFiles, id: \.self) { url in
                            HStack {
                                Toggle("", isOn: Binding(
                                    get: { !excluded.contains(url) },
                                    set: { on in
                                        if on { excluded.remove(url) } else { excluded.insert(url) }
                                    }
                                ))
                                .labelsHidden()
                                .controlSize(.small)
                                Image(systemName: url.pathExtension == "app" ? "app.fill" : "doc")
                                    .foregroundStyle(.secondary)
                                Text(url.path)
                                    .font(.caption).lineLimit(1).truncationMode(.middle)
                                    .help(url.path)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
                .padding(8)
                .background(Theme.inset,
                            in: RoundedRectangle(cornerRadius: 8))

                Text("Seçili \(selectedFiles.count) / \(relatedFiles.count) öğe")
                    .font(.caption).foregroundStyle(.secondary)

                if uninstaller.isRunning(app) {
                    Label("Uygulama şu an açık. Kaldırmadan önce kapatmanız önerilir.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }

                HStack {
                    Spacer()
                    Button("Vazgeç") { showSheet = false }
                    Button("Çöpe Taşı", role: .destructive) { performUninstall() }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedFiles.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var selectedFiles: [URL] { relatedFiles.filter { !excluded.contains($0) } }

    private func prepareUninstall(_ app: InstalledApp) {
        guard uninstaller.protectionReason(for: app) == nil else { return }
        selected = app
        excluded = []
        relatedFiles = uninstaller.relatedFiles(for: app)
        showSheet = true
    }

    private func performUninstall() {
        let result = uninstaller.moveToTrash(selectedFiles)
        resultMessage = "\(result.moved) öğe çöpe taşındı."
        errorMessage = result.errors.isEmpty ? nil : "Bazı öğeler taşınamadı:\n" + result.errors
        showSheet = false
        uninstaller.scan()
    }
}
