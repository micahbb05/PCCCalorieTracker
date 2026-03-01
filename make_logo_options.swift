import AppKit

let outDir = "/Users/micah/Documents/Calorie Tracker/logo-options"
let size = CGSize(width: 1024, height: 1024)
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func contextRep() -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    let url = URL(fileURLWithPath: outDir + "/" + name)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

func roundedRect(_ rect: CGRect, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
}

// Option 1: Fork + leaf
func logo1() {
    let rep = contextRep(); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = CGRect(origin: .zero, size: size)
    NSGradient(starting: NSColor(calibratedRed: 0.07, green: 0.14, blue: 0.34, alpha: 1), ending: NSColor(calibratedRed: 0.17, green: 0.56, blue: 0.40, alpha: 1))?.draw(in: roundedRect(rect, 220), angle: -55)

    let fork = NSBezierPath()
    fork.move(to: CGPoint(x: 470, y: 230)); fork.line(to: CGPoint(x: 470, y: 700)); fork.lineWidth = 34
    NSColor.white.setStroke(); fork.stroke()
    for x in [420.0,470.0,520.0] {
        let tine = NSBezierPath(); tine.move(to: CGPoint(x: x, y: 700)); tine.line(to: CGPoint(x: x, y: 810)); tine.lineWidth = 26; tine.stroke()
    }
    let leaf = NSBezierPath()
    leaf.move(to: CGPoint(x: 560, y: 450)); leaf.curve(to: CGPoint(x: 760, y: 560), controlPoint1: CGPoint(x: 690, y: 390), controlPoint2: CGPoint(x: 800, y: 460))
    leaf.curve(to: CGPoint(x: 560, y: 450), controlPoint1: CGPoint(x: 750, y: 680), controlPoint2: CGPoint(x: 610, y: 610))
    NSColor.white.withAlphaComponent(0.92).setFill(); leaf.fill()
    NSGraphicsContext.restoreGraphicsState(); save(rep, "logo-option-1.png")
}

// Option 2: Minimal C ring
func logo2() {
    let rep = contextRep(); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = CGRect(origin: .zero, size: size)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.23, alpha: 1), ending: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.13, alpha: 1))?.draw(in: roundedRect(rect, 220), angle: -90)
    let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 220, dy: 220)); ring.lineWidth = 90; NSColor(calibratedRed: 0.29, green: 0.84, blue: 0.66, alpha: 1).setStroke(); ring.stroke()
    NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.14, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(x: 510, y: 380, width: 250, height: 260)).fill()
    let t = "C" as NSString
    t.draw(in: CGRect(x: 300, y: 275, width: 420, height: 520), withAttributes: [.font: NSFont.systemFont(ofSize: 420, weight: .heavy), .foregroundColor: NSColor.white.withAlphaComponent(0.95), .paragraphStyle: { let p=NSMutableParagraphStyle(); p.alignment = .center; return p }()])
    NSGraphicsContext.restoreGraphicsState(); save(rep, "logo-option-2.png")
}

// Option 3: Shield + bolt spoon
func logo3() {
    let rep = contextRep(); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = CGRect(origin: .zero, size: size)
    NSGradient(starting: NSColor(calibratedRed: 0.30, green: 0.22, blue: 0.72, alpha: 1), ending: NSColor(calibratedRed: 0.15, green: 0.10, blue: 0.38, alpha: 1))?.draw(in: roundedRect(rect, 220), angle: -80)

    let shield = NSBezierPath()
    shield.move(to: CGPoint(x: 512, y: 820)); shield.line(to: CGPoint(x: 770, y: 700)); shield.line(to: CGPoint(x: 710, y: 380)); shield.curve(to: CGPoint(x: 512, y: 220), controlPoint1: CGPoint(x: 675, y: 300), controlPoint2: CGPoint(x: 580, y: 230)); shield.curve(to: CGPoint(x: 314, y: 380), controlPoint1: CGPoint(x: 444, y: 230), controlPoint2: CGPoint(x: 349, y: 300)); shield.line(to: CGPoint(x: 254, y: 700)); shield.close()
    NSColor.white.withAlphaComponent(0.14).setFill(); shield.fill()

    let spoon = NSBezierPath(ovalIn: CGRect(x: 420, y: 640, width: 180, height: 150)); NSColor.white.setFill(); spoon.fill()
    let stem = NSBezierPath(rect: CGRect(x: 497, y: 360, width: 26, height: 280)); stem.fill()
    let bolt = NSBezierPath()
    bolt.move(to: CGPoint(x: 535, y: 560)); bolt.line(to: CGPoint(x: 470, y: 470)); bolt.line(to: CGPoint(x: 525, y: 470)); bolt.line(to: CGPoint(x: 488, y: 360)); bolt.line(to: CGPoint(x: 565, y: 470)); bolt.line(to: CGPoint(x: 510, y: 470)); bolt.close(); NSColor(calibratedRed: 0.31, green: 0.22, blue: 0.72, alpha: 1).setFill(); bolt.fill()

    NSGraphicsContext.restoreGraphicsState(); save(rep, "logo-option-3.png")
}

// Option 4: Plate + macros bars
func logo4() {
    let rep = contextRep(); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = CGRect(origin: .zero, size: size)
    NSGradient(starting: NSColor(calibratedRed: 0.07, green: 0.27, blue: 0.26, alpha: 1), ending: NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.21, alpha: 1))?.draw(in: roundedRect(rect, 220), angle: -70)

    NSColor.white.withAlphaComponent(0.2).setFill(); NSBezierPath(ovalIn: CGRect(x: 220, y: 300, width: 584, height: 584)).fill()
    NSColor.white.withAlphaComponent(0.95).setFill(); NSBezierPath(ovalIn: CGRect(x: 280, y: 360, width: 464, height: 464)).fill()

    let bars:[(CGFloat,NSColor)] = [
        (0.78, NSColor(calibratedRed: 0.99, green: 0.46, blue: 0.31, alpha: 1)),
        (0.52, NSColor(calibratedRed: 0.16, green: 0.81, blue: 0.57, alpha: 1)),
        (0.36, NSColor(calibratedRed: 0.24, green: 0.56, blue: 0.95, alpha: 1))
    ]
    for (i,b) in bars.enumerated() {
        let y = CGFloat(635 - i*95)
        b.1.setFill()
        roundedRect(CGRect(x: 360, y: y, width: 300*b.0, height: 52), 26).fill()
    }

    NSGraphicsContext.restoreGraphicsState(); save(rep, "logo-option-4.png")
}

logo1(); logo2(); logo3(); logo4()
print(outDir)
