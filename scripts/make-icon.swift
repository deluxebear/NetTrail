// Renders the NetTrail app icon into Trace/Assets.xcassets/AppIcon.appiconset.
// Run: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func render() -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Draw with a top-left origin.
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)

    // macOS icon grid: an 824pt rounded square centred on the canvas, with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.16, green: 0.45, blue: 0.98, alpha: 1),
        CGColor(red: 0.33, green: 0.27, blue: 0.92, alpha: 1),
        CGColor(red: 0.50, green: 0.16, blue: 0.80, alpha: 1),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.minY),
                           end: CGPoint(x: body.maxX, y: body.maxY), options: [])
    // Top sheen.
    let sheen = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.14), CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: 380, y: 160), startRadius: 0,
                           endCenter: CGPoint(x: 380, y: 160), endRadius: 620, options: [])

    // Globe.
    let center = CGPoint(x: 440, y: 580)
    let r: CGFloat = 250
    let globe = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
    ctx.setLineWidth(30)
    ctx.strokeEllipse(in: globe)

    ctx.saveGState()
    ctx.addEllipse(in: globe.insetBy(dx: 15, dy: 15))
    ctx.clip()
    ctx.setAlpha(0.7)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.setLineWidth(20)
    for widthFactor in [0.42, 0.82] as [CGFloat] {
        let w = 2 * r * widthFactor
        ctx.strokeEllipse(in: CGRect(x: center.x - w / 2, y: globe.minY, width: w, height: 2 * r))
    }
    ctx.move(to: CGPoint(x: center.x, y: globe.minY)); ctx.addLine(to: CGPoint(x: center.x, y: globe.maxY))
    for dy in [-0.5, 0, 0.5] as [CGFloat] {
        ctx.move(to: CGPoint(x: globe.minX, y: center.y + dy * r)); ctx.addLine(to: CGPoint(x: globe.maxX, y: center.y + dy * r))
    }
    ctx.strokePath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Trajectory: a dotted trail leaves the globe's right edge and sweeps up to a destination node.
    let angle = -12.0 * CGFloat.pi / 180
    let start = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
    let end = CGPoint(x: 780, y: 250)
    let path = CGMutablePath()
    path.move(to: start)
    path.addCurve(to: end, control1: CGPoint(x: 820, y: 500), control2: CGPoint(x: 860, y: 380))
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: CGColor(red: 0.75, green: 0.95, blue: 1, alpha: 0.9))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.setLineWidth(28)
    ctx.setLineDash(phase: 0, lengths: [0.01, 52])
    ctx.addPath(path)
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: start.x - 30, y: start.y - 30, width: 60, height: 60))
    ctx.fillEllipse(in: CGRect(x: end.x - 56, y: end.y - 56, width: 112, height: 112))
    ctx.restoreGState()
    // Hollow centre on the destination node.
    let inner = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.20, green: 0.43, blue: 0.98, alpha: 1), CGColor(red: 0.30, green: 0.32, blue: 0.94, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: end.x - 26, y: end.y - 26, width: 52, height: 52))
    ctx.clip()
    ctx.drawLinearGradient(inner, start: CGPoint(x: end.x - 24, y: end.y - 24), end: CGPoint(x: end.x + 24, y: end.y + 24), options: [])
    ctx.restoreGState()

    ctx.restoreGState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, size: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    context.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Trace/Assets.xcassets")
let set = root.appendingPathComponent("AppIcon.appiconset")
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
let image = render()
var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        writePNG(image, size: points * scale, to: set.appendingPathComponent(name))
        entries.append("""
            { "idiom" : "mac", "size" : "\(points)x\(points)", "scale" : "\(scale)x", "filename" : "\(name)" }
        """)
    }
}
try! """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
""".write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try! """
{ "info" : { "version" : 1, "author" : "xcode" } }
""".write(to: root.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(set.path)")
