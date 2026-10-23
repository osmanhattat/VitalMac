import SwiftUI
import Charts

// MARK: - Ortak yüzey stili

/// Kartlara uygulanan ortak yüzey: sürekli köşe + ince kenarlık + yumuşak gölge.
/// (Statik; animasyon yok — CPU tavanı sorununu tetiklemez.)
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = 18) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
}

/// Yüzde gösteren dairesel halka göstergesi.
struct RingGauge: View {
    var value: Double          // 0–100
    var label: String
    var color: Color
    var subtitle: String = ""

    private var clamped: Double { min(max(value / 100, 0), 1) }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.14), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0.55), color]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.35), radius: 4)
                VStack(spacing: -1) {
                    Text("\(Int(value.rounded()))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color)
                    Text("%").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            VStack(spacing: 2) {
                Text(label)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .cardSurface()
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
            HStack(spacing: 9) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)
                        .background(
                            tint.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                Text(title).font(.system(.headline, design: .rounded))
                Spacer()
                if let accessory { accessory }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                Text(detail).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.callout)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(colors: [color.opacity(0.7), color],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(4, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 7)
        }
    }
}

/// İstatistik rozeti (küçük etiket + değer).
struct StatBadge: View {
    var label: String
    var value: String
    var color: Color = .secondary

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .underPageBackgroundColor))
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.opacity(0.12))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(color.opacity(0.12), lineWidth: 1)
        )
    }
}
