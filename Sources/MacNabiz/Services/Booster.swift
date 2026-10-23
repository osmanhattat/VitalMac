import Foundation
import AppKit

/// Kapatılabilir arka plan uygulaması (dock'ta görünen, etkin olmayan).
struct BackgroundApp: Identifiable {
    let id: pid_t
    var name: String
    var icon: NSImage?
    var memory: UInt64
}

/// "Hızlandır" eylemleri: bellek temizleme, uygulama/işlem kapatma.
@MainActor
final class Booster: ObservableObject {
    @Published var log: [String] = []
    @Published var isWorking = false

    private func note(_ message: String) {
        log.insert("• \(message)", at: 0)
        if log.count > 50 { log.removeLast() }
    }

    // MARK: - İşlem kapatma

    /// Uygulamayı/işlemi nazikçe kapatır (SIGTERM).
    @discardableResult
    func quit(pid: pid_t, name: String) -> Bool {
        if let reason = protectedReason(pid) { note("\(name): \(reason)"); return false }
        if let app = NSRunningApplication(processIdentifier: pid) {
            let ok = app.terminate()
            note(ok ? "\(name) kapatıldı." : "\(name) kapatılamadı.")
            return ok
        }
        let ok = kill(pid, SIGTERM) == 0
        note(ok ? "\(name) (PID \(pid)) sonlandırıldı." : "\(name) sonlandırılamadı (yetki?).")
        return ok
    }

    /// Uygulamayı/işlemi zorla kapatır (SIGKILL).
    @discardableResult
    func forceKill(pid: pid_t, name: String) -> Bool {
        if let reason = protectedReason(pid) { note("\(name): \(reason)"); return false }
        if let app = NSRunningApplication(processIdentifier: pid) {
            let ok = app.forceTerminate()
            note(ok ? "\(name) zorla kapatıldı." : "\(name) zorla kapatılamadı.")
            return ok
        }
        let ok = kill(pid, SIGKILL) == 0
        note(ok ? "\(name) (PID \(pid)) zorla sonlandırıldı." : "\(name) sonlandırılamadı (yetki?).")
        return ok
    }

    /// Kapatılması sistemi/uygulamanın kendisini bozacak süreçler için gerekçe döndürür.
    private func protectedReason(_ pid: pid_t) -> String? {
        if pid <= 1 { return "sistem süreci (PID \(pid)) kapatılamaz." }
        if pid == ProcessInfo.processInfo.processIdentifier { return "MacNabız kendini kapatamaz." }
        return nil
    }

    // MARK: - Bellek temizleme

    /// `purge` ile inaktif belleği boşaltır (yönetici izni gerektirir).
    /// Şifre penceresi ve purge işlemi arka planda yürür; UI donmaz.
    func purgeMemory(completion: (@MainActor () -> Void)? = nil) {
        Privileged.runAsAdminAsync("/usr/sbin/purge") { [weak self] ok, message in
            self?.note(ok ? "Bellek temizlendi (purge)." : "Bellek temizlenemedi: \(message)")
            completion?()
        }
    }

    // MARK: - Kapatılabilir arka plan uygulamaları

    /// Etkin olmayan, dock'ta görünen kullanıcı uygulamalarını döndürür.
    func backgroundApps(memoryFor: (pid_t) -> UInt64) -> [BackgroundApp] {
        let myPid = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isActive && $0.processIdentifier != myPid }
            .map {
                BackgroundApp(
                    id: $0.processIdentifier,
                    name: $0.localizedName ?? "Bilinmeyen",
                    icon: $0.icon,
                    memory: memoryFor($0.processIdentifier)
                )
            }
            .sorted { $0.memory > $1.memory }
    }

    /// Toplu hızlandırma: seçili uygulamaları kapat, istenirse belleği temizle.
    func boost(quitPids: [(pid_t, String)], purge: Bool) {
        guard !isWorking else { return }
        isWorking = true
        var closed = 0
        for (pid, name) in quitPids where quit(pid: pid, name: name) { closed += 1 }
        if !quitPids.isEmpty { note("\(closed)/\(quitPids.count) uygulama kapatıldı.") }
        let finish: @MainActor () -> Void = { [weak self] in
            self?.note("Hızlandırma tamamlandı.")
            self?.isWorking = false
        }
        if purge { purgeMemory(completion: finish) } else { finish() }
    }
}
