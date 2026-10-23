import SwiftUI
import AppKit

// MARK: - Tasarım belirteçleri
//
// Dil: hasta başı monitörü. Her ölçümün kendi "kanal" rengi vardır; nabız kırmızısı
// yalnızca canlı nabız çizgisi ve seçili durum için kullanılır. Yüzeyler sakin,
// sayılar büyük ve yuvarlak, etiketler küçük, büyük harfli, mono.

enum Theme {
    /// Açık/koyu temaya göre değişen renk.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? dark : light
        })
    }

    private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    // Yüzeyler
    static let canvas  = dynamic(light: hex(0xF3F5F8), dark: hex(0x0D1015))
    static let surface = dynamic(light: hex(0xFFFFFF), dark: hex(0x151A21))
    static let inset   = dynamic(light: hex(0xF1F3F7), dark: hex(0x1B212A))
    static let hairline = dynamic(light: hex(0x0F172A, 0.08), dark: hex(0xFFFFFF, 0.07))
    static let ink     = dynamic(light: hex(0x0F172A), dark: hex(0xE8EDF4))
    static let muted   = dynamic(light: hex(0x5B6577), dark: hex(0x8B95A7))

    // İmza: nabız
    static let pulse   = dynamic(light: hex(0xE11D48), dark: hex(0xFF4D6D))

    // Kanal renkleri
    static let cpu     = dynamic(light: hex(0x0D9488), dark: hex(0x2DD4BF))
    static let memory  = dynamic(light: hex(0x7C3AED), dark: hex(0xA78BFA))
    static let disk    = dynamic(light: hex(0x2563EB), dark: hex(0x60A5FA))
    static let gpu     = dynamic(light: hex(0xD97706), dark: hex(0xFBBF24))
    static let network = dynamic(light: hex(0x059669), dark: hex(0x34D399))
    static let heat    = dynamic(light: hex(0xEA580C), dark: hex(0xFB923C))

    // Durum
    static let ok      = dynamic(light: hex(0x16A34A), dark: hex(0x4ADE80))
    static let warn    = dynamic(light: hex(0xD97706), dark: hex(0xFBBF24))
    static let alert   = dynamic(light: hex(0xDC2626), dark: hex(0xF87171))

    static let radius: CGFloat = 16

    /// Monitör etiketi: küçük, büyük harf, aralıklı mono.
    static func eyebrow(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// Okuma değeri: yuvarlak, kalın, sabit genişlikli rakamlar.
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    /// 0–100 yüzdesine göre durum rengi.
    static func status(_ percent: Double) -> Color {
        switch percent {
        case ..<60: return ok
        case ..<85: return warn
        default:    return alert
        }
    }
}

/// Monitör etiketi metni (büyük harf + harf aralığı). Metin yerelleştirilir;
/// büyük harfe çevirme etkin dile göre yapılır (Türkçe "i" → "İ").
struct Eyebrow: View {
    private let text: Text
    var color: Color = Theme.muted
    var size: CGFloat = 10

    init(_ key: LocalizedStringKey, color: Color = Theme.muted, size: CGFloat = 10) {
        self.text = Text(key); self.color = color; self.size = size
    }

    /// Çevrilmeyecek veri metni (dosya adı, sayı vb.).
    init(verbatim string: String, color: Color = Theme.muted, size: CGFloat = 10) {
        self.text = Text(verbatim: string); self.color = color; self.size = size
    }

    var body: some View {
        text
            .textCase(.uppercase)
            .font(Theme.eyebrow(size))
            .tracking(1.1)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Detay alanının sakin zemin rengi.
struct PageBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Theme.canvas.ignoresSafeArea())
    }
}

extension View {
    func pageBackground() -> some View { modifier(PageBackground()) }
}

// MARK: - İmza: canlı nabız çizgisi

/// Monitördeki gibi soldan sağa süpürülen EKG çizgisi.
/// Atış hızı `bpm` ile verilir (uygulamada CPU yüküne bağlı). Hareket azaltma açıksa
/// sabit bir çizgi çizilir. Kare hızı `fps` ile sınırlıdır; pencere etkin değilken durur.
struct PulseTrace: View {
    var bpm: Double
    var color: Color = Theme.pulse
    var lineWidth: CGFloat = 1.8
    var sweepSeconds: Double = 4
    var fps: Double = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Pencere arka plandayken (etkin değilken) animasyon durur; enerji tasarrufu.
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        if reduceMotion {
            Canvas { ctx, size in draw(ctx, size, now: 1.3, animated: false) }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / fps, paused: activeState == .inactive)) { timeline in
                Canvas { ctx, size in
                    draw(ctx, size, now: timeline.date.timeIntervalSinceReferenceDate, animated: true)
                }
            }
        }
    }

    /// Tek bir kalp atışının dalga biçimi (0…1 faz → genlik, -1…1).
    private static func beat(_ phase: Double) -> Double {
        func bump(_ c: Double, _ w: Double, _ a: Double) -> Double {
            let x = (phase - c) / w
            return a * exp(-x * x)
        }
        return bump(0.18, 0.035, 0.12)     // P dalgası
             + bump(0.30, 0.010, -0.18)    // Q
             + bump(0.33, 0.012, 1.00)     // R
             + bump(0.36, 0.012, -0.30)    // S
             + bump(0.58, 0.060, 0.22)     // T dalgası
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, now: Double, animated: Bool) {
        guard size.width > 4, size.height > 4 else { return }
        let rate = min(max(bpm, 40), 180) / 60.0             // atış / saniye
        let mid = size.height * 0.58
        let amp = size.height * 0.46
        let step: CGFloat = 1.5
        let sweepX = animated
            ? CGFloat((now.truncatingRemainder(dividingBy: sweepSeconds)) / sweepSeconds) * size.width
            : size.width

        // Çizgi zamanı x'e eşler: süpürme noktası "şimdi", solu geçmiş.
        func y(at x: CGFloat) -> CGFloat {
            let secondsAgo = Double((sweepX - x) / size.width) * sweepSeconds
            let t = now - (secondsAgo < 0 ? secondsAgo + sweepSeconds : secondsAgo)
            let phase = (t * rate).truncatingRemainder(dividingBy: 1)
            return mid - CGFloat(Self.beat(phase < 0 ? phase + 1 : phase)) * amp
        }

        var path = Path()
        var x: CGFloat = 0
        path.move(to: CGPoint(x: 0, y: y(at: 0)))
        while x <= size.width {
            path.addLine(to: CGPoint(x: x, y: y(at: x)))
            x += step
        }

        // Süpürme noktasının hemen önü silik (monitördeki boşluk), arkası parlak.
        let gap = size.width * 0.06
        var bright = ctx
        bright.clip(to: Path(CGRect(x: 0, y: 0, width: sweepX, height: size.height)))
        bright.stroke(path, with: .linearGradient(
            Gradient(colors: [color.opacity(0.15), color]),
            startPoint: CGPoint(x: max(0, sweepX - size.width * 0.7), y: 0),
            endPoint: CGPoint(x: sweepX, y: 0)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        if animated, sweepX + gap < size.width {
            var faded = ctx
            faded.clip(to: Path(CGRect(x: sweepX + gap, y: 0, width: size.width - sweepX - gap, height: size.height)))
            faded.stroke(path, with: .color(color.opacity(0.12)),
                         style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }

        // Uç nokta
        let head = CGPoint(x: sweepX, y: y(at: sweepX))
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - 3, y: head.y - 3, width: 6, height: 6)), with: .color(color))
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - 7, y: head.y - 7, width: 14, height: 14)), with: .color(color.opacity(0.18)))
    }
}

/// CPU yükünü dinlenme nabzından (62) yoğun yüke (150) eşler.
enum Pulse {
    static func bpm(forCPU cpu: Double) -> Double { 62 + min(max(cpu, 0), 100) * 0.88 }
}
