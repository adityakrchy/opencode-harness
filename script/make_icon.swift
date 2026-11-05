import AppKit

let size = CGFloat(1024)
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let context = NSGraphicsContext.current!.cgContext
let rect = CGRect(x: 0, y: 0, width: size, height: size)

// Rounded dark base.
let basePath = NSBezierPath(roundedRect: rect.insetBy(dx: 38, dy: 38), xRadius: 228, yRadius: 228)
let baseGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1),
    NSColor(calibratedRed: 0.035, green: 0.038, blue: 0.052, alpha: 1)
])!
baseGradient.draw(in: basePath, angle: -90)

// Warm glow.
context.saveGState()
context.addPath(basePath.cgPath)
context.clip()
let glowColors = [
    NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.12, alpha: 0.72).cgColor,
    NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.10, alpha: 0.0).cgColor
] as CFArray
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0, 1])!
context.drawRadialGradient(glow,
                           startCenter: CGPoint(x: 760, y: 760),
                           startRadius: 12,
                           endCenter: CGPoint(x: 760, y: 760),
                           endRadius: 520,
                           options: [])
let tealColors = [
    NSColor(calibratedRed: 0.15, green: 0.75, blue: 0.72, alpha: 0.32).cgColor,
    NSColor(calibratedRed: 0.15, green: 0.75, blue: 0.72, alpha: 0.0).cgColor
] as CFArray
let teal = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: tealColors, locations: [0, 1])!
context.drawRadialGradient(teal,
                           startCenter: CGPoint(x: 240, y: 240),
                           startRadius: 10,
                           endCenter: CGPoint(x: 240, y: 240),
                           endRadius: 450,
                           options: [])
context.restoreGState()

// Fine grid.
context.saveGState()
context.addPath(basePath.cgPath)
context.clip()
context.setStrokeColor(NSColor.white.withAlphaComponent(0.035).cgColor)
context.setLineWidth(1.5)
for i in stride(from: 160, through: 880, by: 120) {
    context.move(to: CGPoint(x: CGFloat(i), y: 72)); context.addLine(to: CGPoint(x: CGFloat(i), y: 952))
    context.move(to: CGPoint(x: 72, y: CGFloat(i))); context.addLine(to: CGPoint(x: 952, y: CGFloat(i)))
}
context.strokePath()
context.restoreGState()

// Inner highlight border.
let border = NSBezierPath(roundedRect: rect.insetBy(dx: 39, dy: 39), xRadius: 227, yRadius: 227)
NSColor.white.withAlphaComponent(0.12).setStroke()
border.lineWidth = 2
border.stroke()

// Terminal prompt mark.
let chevron = NSBezierPath()
chevron.move(to: CGPoint(x: 305, y: 655))
chevron.line(to: CGPoint(x: 470, y: 512))
chevron.line(to: CGPoint(x: 305, y: 369))
chevron.lineCapStyle = .round
chevron.lineJoinStyle = .round
chevron.lineWidth = 58
NSColor(calibratedWhite: 0.98, alpha: 1).setStroke()
chevron.stroke()

let underscore = NSBezierPath()
underscore.move(to: CGPoint(x: 528, y: 376))
underscore.line(to: CGPoint(x: 718, y: 376))
underscore.lineCapStyle = .round
underscore.lineWidth = 58
NSColor(calibratedRed: 1.0, green: 0.47, blue: 0.16, alpha: 1).setStroke()
underscore.stroke()

// Signal spark.
let spark = NSBezierPath()
spark.move(to: CGPoint(x: 735, y: 704))
spark.line(to: CGPoint(x: 758, y: 758))
spark.line(to: CGPoint(x: 812, y: 781))
spark.line(to: CGPoint(x: 758, y: 804))
spark.line(to: CGPoint(x: 735, y: 858))
spark.line(to: CGPoint(x: 712, y: 804))
spark.line(to: CGPoint(x: 658, y: 781))
spark.line(to: CGPoint(x: 712, y: 758))
spark.close()
NSColor(calibratedRed: 1.0, green: 0.71, blue: 0.35, alpha: 1).setFill()
spark.fill()

// Three status dots.
for (index, color) in [
    NSColor(calibratedRed: 1.0, green: 0.47, blue: 0.16, alpha: 1),
    NSColor(calibratedWhite: 1, alpha: 0.42),
    NSColor(calibratedWhite: 1, alpha: 0.18)
].enumerated() {
    let dot = NSBezierPath(ovalIn: CGRect(x: 316 + CGFloat(index) * 70, y: 222, width: 34, height: 34))
    color.setFill(); dot.fill()
}

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
