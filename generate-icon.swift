import AppKit
import Foundation

// VitalMac uygulama ikonu: yuvarlatılmış kare + turuncu→pembe degrade + beyaz nabız (ECG) çizgisi.

func drawIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: s, height: s)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    // --- Arka plan: yuvarlatılmış kare + degrade ---
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.cgContext.clear(CGRect(x: 0, y: 0, width: s, height: s))

    let margin = s * 0.09
    let rect = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let radius = rect.width * 0.235
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    bg.addClip()
    let grad = NSGradient(colors: [
        NSColor(red: 1.00, green: 0.46, blue: 0.10, alpha: 1),
        NSColor(red: 0.95, green: 0.17, blue: 0.45, alpha: 1)
    ])
    grad?.draw(in: rect, angle: -55)
    NSGraphicsContext.restoreGraphicsState()

    // --- Nabız (ECG) çizgisi ---
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let pts: [(CGFloat, CGFloat)] = [
        (0.15, 0.50), (0.33, 0.50), (0.40, 0.63), (0.47, 0.28),
        (0.55, 0.80), (0.62, 0.40), (0.69, 0.50), (0.85, 0.50)
    ]
    let line = NSBezierPath()
    for (i, p) in pts.enumerated() {
        let point = NSPoint(x: rect.minX + p.0 * rect.width,
                            y: rect.minY + p.1 * rect.height)
        if i == 0 { line.move(to: point) } else { line.line(to: point) }
    }
    line.lineWidth = s * 0.052
    line.lineCapStyle = .round
    line.lineJoinStyle = .round

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = s * 0.018
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()

    NSColor.white.setStroke()
    line.stroke()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

let root = FileManager.default.currentDirectoryPath
let iconset = "\(root)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for (name, px) in sizes {
    guard let data = drawIcon(size: px) else { print("✗ \(name)"); continue }
    try? data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
print("✓ AppIcon.iconset üretildi (\(sizes.count) boyut)")
