import AppKit

// Vector source for WageFlow's clock-and-growth icon. Coordinates use a 1024px canvas.
let output = CommandLine.arguments.dropFirst().first ?? "resource/AppIcon.png"
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                              bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.shouldAntialias = true

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880),
                        xRadius: 196, yRadius: 196)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0.02, 0.20, 0.15, 0.25)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
color(0.05, 0.43, 0.34).setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(0.04, 0.43, 0.35), ending: color(0.17, 0.76, 0.59))!
    .draw(in: tile, angle: 70)

// Soft light at the top keeps the silhouette legible on both light and dark desktops.
NSGraphicsContext.saveGraphicsState()
tile.addClip()
NSGradient(starting: color(0.80, 1, 0.87, 0.18), ending: color(0.80, 1, 0.87, 0))!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: 120, y: 480, width: 880, height: 650)), angle: 270)
NSGraphicsContext.restoreGraphicsState()
let edge = NSBezierPath(roundedRect: NSRect(x: 74, y: 74, width: 876, height: 876),
                        xRadius: 194, yRadius: 194)
color(1, 1, 1, 0.15).setStroke()
edge.lineWidth = 2
edge.stroke()

// A nearly complete clock face: time remains open for the next earned second.
let clock = NSBezierPath()
clock.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 254,
                startAngle: 90, endAngle: 390, clockwise: false)
clock.lineWidth = 42
clock.lineCapStyle = .round
color(0.94, 1, 0.97).setStroke()
clock.stroke()

for angle in [180.0, 270.0] {
    let radians = angle * .pi / 180
    let tick = NSBezierPath()
    tick.move(to: NSPoint(x: 512 + cos(radians) * 200, y: 512 + sin(radians) * 200))
    tick.line(to: NSPoint(x: 512 + cos(radians) * 181, y: 512 + sin(radians) * 181))
    tick.lineWidth = 10
    tick.lineCapStyle = .round
    color(0.90, 1, 0.95, 0.40).setStroke()
    tick.stroke()
}

// The flowing W doubles as an upward income chart, with a gold coin at its tip.
let flow = NSBezierPath()
flow.move(to: NSPoint(x: 351, y: 555))
flow.line(to: NSPoint(x: 413, y: 430))
flow.curve(to: NSPoint(x: 441, y: 430), controlPoint1: NSPoint(x: 420, y: 416),
           controlPoint2: NSPoint(x: 434, y: 416))
flow.line(to: NSPoint(x: 500, y: 537))
flow.curve(to: NSPoint(x: 526, y: 540), controlPoint1: NSPoint(x: 507, y: 550),
           controlPoint2: NSPoint(x: 518, y: 552))
flow.line(to: NSPoint(x: 569, y: 478))
flow.curve(to: NSPoint(x: 597, y: 480), controlPoint1: NSPoint(x: 577, y: 466),
           controlPoint2: NSPoint(x: 590, y: 465))
flow.line(to: NSPoint(x: 673, y: 622))
flow.lineWidth = 35
flow.lineCapStyle = .round
flow.lineJoinStyle = .round
color(1, 0.86, 0.45).setStroke()
flow.stroke()
let coin = NSBezierPath(ovalIn: NSRect(x: 690, y: 668, width: 76, height: 76))
NSGradient(starting: color(1, 0.78, 0.30), ending: color(1, 0.94, 0.66))!
    .draw(in: coin, angle: 90)

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode app icon")
}
try png.write(to: URL(fileURLWithPath: output))
print("Rendered \(output)")
