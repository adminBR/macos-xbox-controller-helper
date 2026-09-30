import AppKit
import Foundation

// Original vector artwork, rendered at each macOS icon resolution.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(deviceRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func render(_ pixels: Int, _ filename: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 208, yRadius: 208)
    NSGradient(starting: color(0x142034), ending: color(0x22344F))!.draw(in: background, angle: 90)
    let body = NSBezierPath()
    body.move(to: NSPoint(x: 310, y: 700))
    body.curve(to: NSPoint(x: 235, y: 627), controlPoint1: NSPoint(x: 268, y: 700), controlPoint2: NSPoint(x: 248, y: 674))
    body.line(to: NSPoint(x: 163, y: 401))
    body.curve(to: NSPoint(x: 236, y: 309), controlPoint1: NSPoint(x: 138, y: 326), controlPoint2: NSPoint(x: 191, y: 278))
    body.curve(to: NSPoint(x: 365, y: 433), controlPoint1: NSPoint(x: 273, y: 335), controlPoint2: NSPoint(x: 328, y: 397))
    body.line(to: NSPoint(x: 659, y: 433))
    body.curve(to: NSPoint(x: 788, y: 309), controlPoint1: NSPoint(x: 696, y: 397), controlPoint2: NSPoint(x: 751, y: 335))
    body.curve(to: NSPoint(x: 861, y: 401), controlPoint1: NSPoint(x: 833, y: 278), controlPoint2: NSPoint(x: 886, y: 326))
    body.line(to: NSPoint(x: 789, y: 627))
    body.curve(to: NSPoint(x: 714, y: 700), controlPoint1: NSPoint(x: 776, y: 674), controlPoint2: NSPoint(x: 756, y: 700))
    body.close()
    NSGradient(starting: color(0x087CFF), ending: color(0x2F9FFF))!.draw(in: body, angle: 90)
    color(0x17304B).setStroke()
    let dpad = NSBezierPath()
    dpad.lineWidth = 28
    dpad.lineCapStyle = .round
    dpad.move(to: NSPoint(x: 350, y: 590)); dpad.line(to: NSPoint(x: 350, y: 500))
    dpad.move(to: NSPoint(x: 305, y: 545)); dpad.line(to: NSPoint(x: 395, y: 545))
    dpad.stroke()
    color(0x17304B).setFill()
    for (x, y, radius) in [(674.0, 594.0, 20.0), (723, 545, 20), (674, 496, 20), (625, 545, 20), (449, 490, 22), (557, 490, 22)] {
        NSBezierPath(ovalIn: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
    }
    NSBezierPath(roundedRect: NSRect(x: 490, y: 607, width: 44, height: 12), xRadius: 6, yRadius: 6).fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
}

for size in [16, 32, 128, 256, 512] {
    try render(size, "icon_\(size)x\(size).png")
    try render(size * 2, "icon_\(size)x\(size)@2x.png")
}
