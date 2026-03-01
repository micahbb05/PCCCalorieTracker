import AppKit

let outPath = "/Users/micah/Documents/Calorie Tracker/temp photos/fork-knife-logo.png"
let size = CGSize(width: 1024, height: 1024)

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
    fatalError("Failed to create bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = CGRect(origin: .zero, size: size)
let rounded = NSBezierPath(roundedRect: canvas, xRadius: 220, yRadius: 220)
let bg = NSGradient(
    starting: NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.44, alpha: 1),
    ending: NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.27, alpha: 1)
)
bg?.draw(in: rounded, angle: -70)

let plateOuter = NSBezierPath(ovalIn: CGRect(x: 210, y: 210, width: 604, height: 604))
NSColor.white.withAlphaComponent(0.22).setFill()
plateOuter.fill()

let plateInner = NSBezierPath(ovalIn: CGRect(x: 268, y: 268, width: 488, height: 488))
NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.0, alpha: 1).setFill()
plateInner.fill()

let ring = NSBezierPath(ovalIn: CGRect(x: 300, y: 300, width: 424, height: 424))
ring.lineWidth = 8
NSColor(calibratedRed: 0.76, green: 0.84, blue: 0.95, alpha: 1).setStroke()
ring.stroke()

// Fork (left)
NSColor(calibratedRed: 0.17, green: 0.26, blue: 0.43, alpha: 1).setFill()
let forkStem = NSBezierPath(roundedRect: CGRect(x: 395, y: 355, width: 24, height: 300), xRadius: 12, yRadius: 12)
forkStem.fill()
for x in [386.0, 404.0, 422.0] {
    let tine = NSBezierPath(roundedRect: CGRect(x: x, y: 650, width: 10, height: 96), xRadius: 5, yRadius: 5)
    tine.fill()
}

// Knife (right)
let knifeHandle = NSBezierPath(roundedRect: CGRect(x: 520, y: 355, width: 24, height: 190), xRadius: 12, yRadius: 12)
knifeHandle.fill()
let knifeBlade = NSBezierPath()
knifeBlade.move(to: CGPoint(x: 532, y: 740))
knifeBlade.line(to: CGPoint(x: 562, y: 705))
knifeBlade.line(to: CGPoint(x: 562, y: 520))
knifeBlade.curve(to: CGPoint(x: 532, y: 540), controlPoint1: CGPoint(x: 552, y: 530), controlPoint2: CGPoint(x: 540, y: 535))
knifeBlade.close()
NSColor(calibratedRed: 0.22, green: 0.32, blue: 0.51, alpha: 1).setFill()
knifeBlade.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode PNG")
}
try png.write(to: URL(fileURLWithPath: outPath))
print(outPath)
