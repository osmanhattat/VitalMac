import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var notify: NotificationManager

    @AppStorage(SettingsKey.notifyEnabled) private var notifyEnabled = false
    @AppStorage(SettingsKey.notifyCPU) private var cpuLimit = 90.0
    @AppStorage(SettingsKey.notifyMem) private var memLimit = 85.0
    @AppStorage(SettingsKey.notifyDisk) private var diskLimit = 90.0
    @AppStorage(SettingsKey.notifyTemp) private var tempLimit = 90.0
    @AppStorage(SettingsKey.autoCleanEnabled) private var autoClean = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Bildirimler
                Card(title: "Eşik Bildirimleri", systemImage: "bell.badge") {
                    Toggle(isOn: $notifyEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bildirimleri aç")
                            Text("Bir değer eşiği aştığında masaüstü bildirimi gönderilir.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: notifyEnabled) { _, on in
                        if on { notify.requestAuthorization() }
                    }

                    if notifyEnabled {
                        Divider()
                        thresholdSlider(String(localized: "İşlemci (CPU)"), value: $cpuLimit, range: 50...100, unit: "%")
                        thresholdSlider("Bellek", value: $memLimit, range: 50...100, unit: "%")
                        thresholdSlider(String(localized: "Disk doluluk"), value: $diskLimit, range: 70...99, unit: "%")
                        thresholdSlider(String(localized: "CPU sıcaklığı"), value: $tempLimit, range: 70...110, unit: "°C")
                    }
                }

                // Otomatik bakım
                Card(title: "Otomatik Bakım", systemImage: "clock.arrow.circlepath") {
                    Toggle(isOn: $autoClean) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Haftalık otomatik temizlik")
                            Text("Yeniden oluşturulabilen önbellek / log / DerivedData Çöp Kutusu'na taşınır. Açık uygulamaların ve Apple'ın önbellekleri ile kişisel dosyalara dokunulmaz.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if autoClean {
                        let last = UserDefaults.standard.double(forKey: SettingsKey.autoCleanLast)
                        Text(last > 0
                             ? "Son çalışma: \(relativeDate(last))"
                             : "Henüz çalışmadı; uygulama açıldığında zamanı gelince çalışır.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Hakkında
                Card(title: "Hakkında", systemImage: "info.circle") {
                    InfoRow(label: "Uygulama", value: "VitalMac 1.0")
                    InfoRow(label: "Motor", value: "SwiftUI · mach · libproc · IOKit")
                    Text("Tüm ölçümler sudo gerektirmeden okunur. Silme işlemleri her zaman onay ister.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .navigationTitle("Ayarlar")
    }

    private func thresholdSlider(_ label: String, value: Binding<Double>,
                                 range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)").font(.callout.bold()).monospacedDigit()
            }
            Slider(value: value, in: range, step: 1)
        }
    }

    private func relativeDate(_ ts: Double) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.localizedString(for: Date(timeIntervalSince1970: ts), relativeTo: Date())
    }
}
