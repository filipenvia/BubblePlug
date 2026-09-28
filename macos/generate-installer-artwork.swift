import AppKit
import Foundation

let scriptDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let logoURL = scriptDirectory
    .appendingPathComponent("Sources/BubblePlugApp/Resources/BubblePlug.png")
let outputDirectory = scriptDirectory.appendingPathComponent("installer-resources")
let outputURL = outputDirectory.appendingPathComponent("BubblePlug-Installer.png")

guard let logo = NSImage(contentsOf: logoURL) else {
    fatalError("Could not load BubblePlug logo at \(logoURL.path)")
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let size = NSSize(width: 320, height: 600)
let scale = 3
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width) * scale,
    pixelsHigh: Int(size.height) * scale,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create installer artwork bitmap")
}

let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

let panel = NSRect(origin: .zero, size: size)
NSGradient(colors: [
    NSColor(calibratedRed: 0.055, green: 0.145, blue: 0.31, alpha: 1),
    NSColor(calibratedRed: 0.025, green: 0.065, blue: 0.15, alpha: 1),
    NSColor(calibratedRed: 0.012, green: 0.027, blue: 0.075, alpha: 1),
])!.draw(in: panel, angle: 90)

NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.94, alpha: 0.34),
    NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.94, alpha: 0.0),
])!.draw(
    fromCenter: NSPoint(x: 160, y: 365),
    radius: 8,
    toCenter: NSPoint(x: 160, y: 365),
    radius: 235,
    options: [.drawsAfterEndingLocation]
)

func drawArc(_ points: [NSPoint], color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.move(to: points[0])
    path.curve(to: points[3], controlPoint1: points[1], controlPoint2: points[2])
    color.setStroke()
    path.stroke()
}

drawArc(
    [NSPoint(x: -30, y: 72), NSPoint(x: 68, y: 122), NSPoint(x: 218, y: 20), NSPoint(x: 354, y: 88)],
    color: NSColor(calibratedRed: 0.24, green: 0.79, blue: 1, alpha: 0.32),
    width: 1.4
)
drawArc(
    [NSPoint(x: -28, y: 56), NSPoint(x: 94, y: 92), NSPoint(x: 214, y: 4), NSPoint(x: 350, y: 64)],
    color: NSColor(calibratedRed: 0.75, green: 0.42, blue: 1, alpha: 0.2),
    width: 1
)

func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor, tracking: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributed.size()
    attributed.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: y))
}

drawCentered(
    "ABLETON LIVE COMPANION",
    y: 545,
    font: .systemFont(ofSize: 10, weight: .semibold),
    color: NSColor(calibratedRed: 0.36, green: 0.85, blue: 0.98, alpha: 1),
    tracking: 2.0
)

let logoRect = NSRect(x: 48, y: 286, width: 224, height: 224)
logo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1)

drawCentered(
    "BubblePlug",
    y: 218,
    font: .systemFont(ofSize: 29, weight: .bold),
    color: NSColor(calibratedRed: 0.94, green: 0.97, blue: 1, alpha: 1),
    tracking: -0.5
)
drawCentered(
    "Your plugins. In your flow.",
    y: 184,
    font: .systemFont(ofSize: 14, weight: .regular),
    color: NSColor(calibratedRed: 0.72, green: 0.81, blue: 0.94, alpha: 1)
)

let accent = NSBezierPath(roundedRect: NSRect(x: 133, y: 151, width: 54, height: 2), xRadius: 1, yRadius: 1)
NSColor(calibratedRed: 0.39, green: 0.82, blue: 1, alpha: 0.9).setFill()
accent.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode installer artwork as PNG")
}
try png.write(to: outputURL, options: .atomic)
print("Wrote \(outputURL.path) (\(Int(size.width) * scale) × \(Int(size.height) * scale))")
