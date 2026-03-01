import AppKit

struct Palette {
    let top: NSColor
    let bottom: NSColor
    let glyph: NSColor
}

let outputDir = "/Users/micah/Documents/Calorie Tracker/Calorie Tracker/Assets.xcassets/AppIcon.appiconset"
let size = CGSize(width: 1024, height: 1024)

let palettes: [(String, Palette)] = [
    ("icon.png", Palette(
        top: NSColor(calibratedRed: 0.12, green: 0.33, blue: 0.86, alpha: 1),
        bottom: NSColor(calibratedRed: 0.06, green: 0.15, blue: 0.42, alpha: 1),
        glyph: .white
    )),
    ("icon-dark.png", Palette(
        top: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.25, alpha: 1),
        bottom: NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 1),
        glyph: NSColor(calibratedRed: 0.78, green: 0.86, blue: 1.0, alpha: 1)
    )),
    ("icon-tinted.png", Palette(
        top: NSColor(calibratedRed: 0.17, green: 0.55, blue: 0.52, alpha: 1),
        bottom: NSColor(calibratedRed: 0.05, green: 0.28, blue: 0.29, alpha: 1),
        glyph: NSColor(calibratedRed: 0.95, green: 1.0, blue: 0.98, alpha: 1)
    ))
]

func renderIcon(_ palette: Palette, to path: String) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "icon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = CGRect(origin: .zero, size: size)

    let background = NSBezierPath(roundedRect: rect, xRadius: 224, yRadius: 224)
    let gradient = NSGradient(starting: palette.top, ending: palette.bottom)
    gradient?.draw(in: background, angle: -90)

    let ringRect = rect.insetBy(dx: 190, dy: 190)
    let ring = NSBezierPath(ovalIn: ringRect)
    NSColor.white.withAlphaComponent(0.13).setFill()
    ring.fill()

    let innerRect = rect.insetBy(dx: 244, dy: 244)
    let inner = NSBezierPath(ovalIn: innerRect)
    NSColor.black.withAlphaComponent(0.15).setFill()
    inner.fill()

    let glyph = "CT"
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 286, weight: .heavy),
        .foregroundColor: palette.glyph,
        .paragraphStyle: paragraph
    ]
    let textRect = CGRect(x: 0, y: 334, width: size.width, height: 360)
    glyph.draw(in: textRect, withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 2)
    }
    try png.write(to: URL(fileURLWithPath: path))
}

for (name, palette) in palettes {
    try renderIcon(palette, to: outputDir + "/" + name)
}
