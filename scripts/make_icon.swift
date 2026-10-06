// Renders the app icon into an .iconset folder.
// Usage: swift scripts/make_icon.swift <out.iconset>
import AppKit

let outDir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024) // draw in a 1024pt space at any pixel size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Body: macOS icon grid (824pt rounded square on a 1024pt canvas) with a soft drop shadow.
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(srgbRed: 0.07, green: 0.45, blue: 0.33, alpha: 1).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.72, blue: 0.52, alpha: 1),
               ending: NSColor(srgbRed: 0.04, green: 0.40, blue: 0.30, alpha: 1))!
        .draw(in: body, angle: -90)

    // Donut chart: three segments of decreasing weight with small gaps.
    let center = NSPoint(x: 512, y: 512)
    let radius: CGFloat = 235
    let width: CGFloat = 118
    var angle: CGFloat = 90
    for (sweep, alpha) in [(190.0, 1.0), (105.0, 0.72), (65.0, 0.45)] {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: angle - 6, endAngle: angle - CGFloat(sweep) + 6, clockwise: true)
        arc.lineWidth = width
        arc.lineCapStyle = .butt
        NSColor.white.withAlphaComponent(alpha).setStroke()
        arc.stroke()
        angle -= CGFloat(sweep)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, pixels) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    try render(pixels: pixels).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
