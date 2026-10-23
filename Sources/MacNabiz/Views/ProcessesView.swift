import SwiftUI

struct ProcessesView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @ObservedObject var booster: Booster

    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\ProcInfo.cpu, order: .reverse)]
    @State private var selection: ProcInfo.ID?
    @State private var confirmTarget: ProcInfo?
    @State private var forceMode = false

    private var filtered: [ProcInfo] {
        let base = search.isEmpty
            ? monitor.processes
            : monitor.processes.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return base.sorted(using: sortOrder)
    }

    private var selectedProc: ProcInfo? {
        guard let selection else { return nil }
        return monitor.processes.first { $0.id == selection }
    }

    @State private var actionResult: (ok: Bool, message: String)?

    var body: some View {
        VStack(spacing: 0) {
            header

            Table(filtered, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("İşlem") { proc in
                    HStack(spacing: 8) {
                        if let img = proc.icon {
                            Image(nsImage: img).resizable().frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "gearshape.2").foregroundStyle(.secondary)
                        }
                        Text(proc.name).lineLimit(1)
                        if proc.isApp {
                            Text("uygulama")
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.blue.opacity(0.18), in: Capsule())
                        }
                    }
                }
                TableColumn("CPU", value: \.cpu) { proc in
                    Text(Fmt.percent1(proc.cpu)).monospacedDigit()
                        .foregroundStyle(proc.cpu > 50 ? .red : .primary)
                }
                .width(72)
                TableColumn("Bellek", value: \.memory) { proc in
                    Text(Fmt.bytes(proc.memory)).monospacedDigit()
                }
                .width(100)
                TableColumn("PID", value: \.pid) { proc in
                    Text("\(proc.pid)").monospacedDigit().foregroundStyle(.secondary)
                }
                .width(70)
            }
            .tableStyle(.inset)

            footer
        }
        .navigationTitle("İşlemler")
        .confirmationDialog(
            confirmTarget.map { "“\($0.name)” işlemini \(forceMode ? "zorla " : "")kapat?" } ?? "",
            isPresented: Binding(
                get: { confirmTarget != nil },
                set: { if !$0 { confirmTarget = nil } }
            ),
            presenting: confirmTarget
        ) { proc in
            Button(forceMode ? "Zorla Kapat" : "Kapat", role: .destructive) {
                let ok = forceMode ? booster.forceKill(pid: proc.pid, name: proc.name)
                                   : booster.quit(pid: proc.pid, name: proc.name)
                // Sonucu kullanıcıya göster (Booster günlüğündeki son satır ayrıntıyı içerir).
                actionResult = (ok, booster.log.first.map { String($0.dropFirst(2)) } ?? "")
                selection = nil
            }
            Button("Vazgeç", role: .cancel) { }
        } message: { proc in
            Text("PID \(proc.pid) — kaydedilmemiş veriler kaybolabilir.")
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("İşlem ara…", text: $search)
                .textFieldStyle(.plain)
            Spacer()
            Text("\(filtered.count) işlem")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var footer: some View {
        HStack {
            if let result = actionResult, selectedProc == nil {
                Label(result.message, systemImage: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(result.ok ? .green : .orange).lineLimit(1)
            } else if let proc = selectedProc {
                Text("Seçili: \(proc.name)  ·  \(Fmt.percent1(proc.cpu))  ·  \(Fmt.bytes(proc.memory))")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Bir işlem seçin").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                forceMode = false
                confirmTarget = selectedProc
            } label: {
                Label("Kapat", systemImage: "xmark.circle")
            }
            .disabled(selectedProc == nil)

            Button(role: .destructive) {
                forceMode = true
                confirmTarget = selectedProc
            } label: {
                Label("Zorla Kapat", systemImage: "xmark.octagon.fill")
            }
            .disabled(selectedProc == nil)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
