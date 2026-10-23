import SwiftUI
import AppKit

struct CleanerView: View {
    @ObservedObject var cleaner: CacheCleaner
    @State private var confirmClean = false
    @State private var resultMessage: String?

    private var selectedSize: Int64 {
        cleaner.targets.filter { $0.enabled }.reduce(0) { $0 + $1.size }
    }
    private var selectedCount: Int {
        cleaner.targets.filter { $0.enabled }.reduce(0) { $0 + $1.items.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if cleaner.scanning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Taranıyor… içerik dökümü çıkarılıyor").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cleaner.targets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach($cleaner.targets) { $target in
                            CleanTargetCard(target: $target)
                        }
                        if let resultMessage {
                            Label(resultMessage, systemImage: "checkmark.circle.fill")
                                .font(.callout).foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Temizlik")
        .onAppear { if cleaner.targets.isEmpty { cleaner.scan() } }
        .confirmationDialog(
            "\(selectedCount) öğe silinecek (\(Fmt.bytes(selectedSize)))",
            isPresented: $confirmClean,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                cleaner.cleanSelected { freed, failures in
                    var text = String(localized: "\(Fmt.bytes(freed)) yer açıldı.")
                    if !failures.isEmpty {
                        text += String(localized: " \(failures.count) öğe kullanımda olduğu için silinemedi.")
                    }
                    resultMessage = text
                    cleaner.scan()
                }
            }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Listelenen öğeler kaldırılır. Çöp kutusu kalıcı boşalır; önbellek/log dosyaları silinir.")
        }
    }

    private var toolbar: some View {
        HStack {
            Button { resultMessage = nil; cleaner.scan() } label: {
                Label("Yeniden Tara", systemImage: "arrow.clockwise")
            }
            Spacer()
            Text("\(selectedCount) öğe · \(Fmt.bytes(selectedSize))")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Button { confirmClean = true } label: {
                Label("Seçilenleri Sil", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSize == 0 || cleaner.cleaning)
            if cleaner.cleaning { ProgressView().controlSize(.small) }
        }
        .padding(10)
        .background(Theme.surface)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Temizlenecek bir şey bulunamadı").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Tek bir temizlik hedefi: başlık + güvenlik notu + açılır içerik dökümü.
private struct CleanTargetCard: View {
    @Binding var target: CleanTarget
    @State private var expanded = false

    private let previewLimit = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Başlık — sayıya/başlığa tıklayınca döküm açılır
            HStack(spacing: 12) {
                Toggle("", isOn: $target.enabled).labelsHidden()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.name).font(.headline)
                            Text(target.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Fmt.bytes(target.size)).font(.headline).monospacedDigit()
                            HStack(spacing: 3) {
                                Text("\(target.items.count) öğe").font(.caption2)
                                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                            }
                            .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Güvenlik notu
            Label(target.note, systemImage: target.name == "Çöp Kutusu" ? "exclamationmark.triangle" : "info.circle")
                .font(.caption)
                .foregroundStyle(target.name == "Çöp Kutusu" ? .orange : .secondary)
                .padding(.top, 8)

            if !expanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded = true }
                } label: {
                    Text("Ne silinecek? (\(target.items.count) öğe göster)")
                        .font(.caption).foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            } else {
                // Döküm
                VStack(spacing: 0) {
                    ForEach(target.items.prefix(previewLimit)) { item in
                        HStack {
                            Image(systemName: item.isDirectory ? "folder" : "doc")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(item.name).font(.caption).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Fmt.bytes(item.size)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        Divider()
                    }
                    if target.items.count > previewLimit {
                        let rest = target.items.count - previewLimit
                        let restSize = target.items.dropFirst(previewLimit).reduce(0) { $0 + $1.size }
                        Text("+ \(rest) öğe daha (\(Fmt.bytes(restSize)))")
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(14)
        .background(Theme.surface,
                    in: RoundedRectangle(cornerRadius: 12))
    }
}
