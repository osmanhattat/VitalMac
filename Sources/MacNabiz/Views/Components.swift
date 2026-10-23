import SwiftUI
import Charts

// MARK: - Ortak yüzey stili

/// Kartlara uygulanan ortak yüzey: sakin zemin + ince kenar. Gölge yok (monitör camı gibi düz).
/// (Statik; animasyon yok — CPU tavanı sorununu tetiklemez.)
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.radius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = Theme.radius) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
}

/// Monitör kanalı: etiket, büyük okuma, alt bilgi ve mini geçmiş çizgisi.
struct VitalChannel: View {
    var label: String
    var value: Double              // 0–100
    var unit: String = "%"
    var detail: String
    var color: Color
    var history: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Eyebrow(label)
                Spacer(minLength: 0)
                if value >= 85 {
                    Eyebrow("yüksek", color: Theme.alert, size: 9)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(value.rounded()))")
                    .font(Theme.readout(40))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(Theme.readout(16))
                    .foregroundStyle(color.opacity(0.7))
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            if history.isEmpty {
                // Geçmişi olmayan kanal (disk) doluluk çubuğu gösterir.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.inset)
                        Capsule().fill(color).frame(width: max(3, geo.size.width * min(max(value / 100, 0), 1)))
                    }
                }
                .frame(height: 6)
                .padding(.vertical, 10)
            } else {
                MiniTrace(data: history, color: color)
                    .frame(height: 26)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Eksensiz, hafif mini geçmiş çizgisi (0–100).
struct MiniTrace: View {
    var data: [Double]
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let points = data.suffix(60)
            guard points.count > 1 else {
                var base = Path()
                base.move(to: CGPoint(x: 0, y: size.height - 1))
                base.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                ctx.stroke(base, with: .color(color.opacity(0.2)), lineWidth: 1)
                return
            }
            let dx = size.width / CGFloat(points.count - 1)
            var line = Path()
            for (i, v) in points.enumerated() {
                let p = CGPoint(x: CGFloat(i) * dx,
                                y: size.height - CGFloat(min(max(v, 0), 100) / 100) * (size.height - 2) - 1)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.22), color.opacity(0)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }
    }
}

/// Başlıklı kart kapsayıcısı.
struct Card<Content: View>: View {
    var title: String
    var systemImage: String? = nil
    var tint: Color = .secondary
    var accessory: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint == .secondary ? Theme.muted : tint)
                        .frame(width: 14)
                }
                Eyebrow(title, color: Theme.muted, size: 10.5)
                Spacer()
                if let accessory { accessory }
            }
            content()
        }
        .padding(18)
        // Yan yana kartlar (fixedSize'lı HStack içinde) eşit yükseklikte durur.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
    }
}

/// 0–100 aralığında alan + çizgi grafiği (mini geçmiş).
struct Sparkline: View {
    var data: [Double]
    var color: Color

    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("t", index), y: .value("v", value))
                .foregroundStyle(
                    LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )
            LineMark(x: .value("t", index), y: .value("v", value))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.linear)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { _ in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel()
            }
        }
        .frame(height: 90)
        .animation(nil, value: data)        // örtük animasyonu kapat (CPU tasarrufu)
    }
}

/// Otomatik ölçeklenen alan grafiği (ağ hızı gibi sınırsız değerler için).
struct AutoSparkline: View {
    var data: [Double]
    var color: Color

    private var maxValue: Double { max(data.max() ?? 1, 1) }

    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("t", index), y: .value("v", value))
                .foregroundStyle(
                    LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )
            LineMark(x: .value("t", index), y: .value("v", value))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.linear)
        }
        .chartYScale(domain: 0...maxValue)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 60)
        .animation(nil, value: data)        // örtük animasyonu kapat (CPU tasarrufu)
    }
}

/// Etiket + oransal dolgu çubuğu (disk/temizlik listelerinde).
struct ProportionRow: View {
    var title: String
    var detail: String
    var fraction: Double      // 0–1
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).lineLimit(1).foregroundStyle(Theme.ink)
                Spacer()
                Text(detail).foregroundStyle(Theme.muted).monospacedDigit()
            }
            .font(.callout)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inset)
                    Capsule()
                        .fill(color)
                        .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 5)
        }
    }
}

/// İstatistik rozeti: küçük mono etiket + değer (monitör okuması).
struct StatBadge: View {
    var label: String
    var value: String
    var color: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(label, size: 9)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color == .secondary ? Theme.ink : color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
