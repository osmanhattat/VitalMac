import SwiftUI

struct StartupView: View {
    @ObservedObject var loginItems: LoginItemsService

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = loginItems.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                Card(title: "VitalMac", systemImage: "power") {
                    Toggle(isOn: Binding(
                        get: { loginItems.launchAtLogin },
                        set: { loginItems.setLaunchAtLogin($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Oturum açıldığında VitalMac'ı başlat")
                            Text("Menü çubuğundan sistemini sürekli izleyebilirsin.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Card(title: "Kullanıcı Başlangıç Ajanları", systemImage: "list.bullet") {
                    if loginItems.loading && loginItems.agents.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Ajanlar okunuyor…").font(.callout).foregroundStyle(.secondary)
                        }
                    } else if loginItems.agents.isEmpty {
                        Text("~/Library/LaunchAgents içinde öğe bulunamadı.")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        Text("Oturum açıldığında çalışan arka plan ajanları. Anahtar, ajanın şu an yüklü olup olmadığını gösterir; değiştirmek launchctl ile kalıcı olarak yapılır.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(loginItems.agents) { agent in
                            HStack {
                                Image(systemName: agent.loaded ? "gearshape.fill" : "gearshape")
                                    .foregroundStyle(agent.loaded ? Color.green : Color.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(agent.label).font(.callout).lineLimit(1)
                                    Text(agent.loaded ? "Yüklü" : "Yüklü değil")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if loginItems.busyAgents.contains(agent.id) {
                                    ProgressView().controlSize(.small)
                                }
                                Toggle("", isOn: Binding(
                                    get: { agent.loaded },
                                    set: { loginItems.setAgent(agent, enabled: $0) }
                                ))
                                .labelsHidden()
                                .disabled(loginItems.busyAgents.contains(agent.id))
                            }
                            .padding(.vertical, 2)
                            .contextMenu {
                                Button("Finder'da Göster") {
                                    NSWorkspace.shared.activateFileViewerSelecting([agent.path])
                                }
                            }
                            Divider()
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Başlangıç")
        .toolbar {
            Button { loginItems.refresh() } label: {
                Label("Yenile", systemImage: "arrow.clockwise")
            }
        }
        .onAppear { loginItems.refresh() }
    }
}
