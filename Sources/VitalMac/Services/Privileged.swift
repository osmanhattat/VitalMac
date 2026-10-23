import Foundation

/// Yönetici izni gerektiren komutları ve normal komut çağrılarını çalıştırır.
/// Yönetici izni macOS şifre penceresiyle (osascript `with administrator privileges`) alınır.
///
/// Güvenlik: komutlar hiçbir zaman metin birleştirmeyle kabuğa verilmez. Program yolu ve
/// her argüman osascript'e ayrı `argv` öğesi olarak geçer ve AppleScript tarafında
/// `quoted form of` ile tek tek tırnaklanır; bu yüzden argüman içeriği kabuk/AppleScript
/// enjeksiyonuna yol açamaz.
enum Privileged {

    /// AppleScript: argv[1] program, kalanı argümanlar; hepsi ayrı ayrı tırnaklanır.
    private static let adminScript = """
    on run argv
        set cmd to quoted form of (item 1 of argv)
        repeat with i from 2 to count of argv
            set cmd to cmd & " " & quoted form of (item i of argv)
        end repeat
        return do shell script cmd with administrator privileges
    end run
    """

    /// Programı yönetici (root) yetkisiyle çalıştırır. Sistem şifre penceresi açılır.
    /// Senkron çalışır; ana iş parçacığında ÇAĞIRMAYIN (bkz. `runAsAdminAsync`).
    /// - Parameters:
    ///   - executable: Mutlak program yolu (örn. "/usr/sbin/purge").
    ///   - args: Argümanlar (tırnaklama otomatik yapılır).
    static func runAsAdmin(_ executable: String, _ args: [String] = []) -> (ok: Bool, message: String) {
        guard executable.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: executable) else {
            return (false, String(localized: "Geçersiz program yolu: \(executable)"))
        }
        let result = runShell("/usr/bin/osascript", ["-e", adminScript, executable] + args)
        if result.status == 0 {
            return (true, result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // Kullanıcı şifre penceresini iptal ederse osascript "(-128)" ile döner.
        if result.output.contains("-128") {
            return (false, String(localized: "Kullanıcı iptal etti."))
        }
        let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, message.isEmpty ? String(localized: "Bilinmeyen hata (kod \(result.status))") : message)
    }

    /// `runAsAdmin`'i arka planda çalıştırır, sonucu ana iş parçacığında bildirir.
    static func runAsAdminAsync(_ executable: String, _ args: [String] = [],
                                completion: @escaping @MainActor (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = runAsAdmin(executable, args)
            Task { @MainActor in completion(result.ok, result.message) }
        }
    }

    /// Normal (yetkisiz) bir programı çalıştırır ve birleşik stdout+stderr çıktısını döndürür.
    /// Çıktı, süreç bitmeden okunur; böylece 64 KB'lık pipe tamponu dolup kilitlenme olmaz.
    @discardableResult
    static func runShell(_ launchPath: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, String(localized: "\(launchPath) çalıştırılamadı: \(error.localizedDescription)"))
        }
        // Önce EOF'a kadar oku (süreç kapanınca EOF gelir), sonra bekle.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
