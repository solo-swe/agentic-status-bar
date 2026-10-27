// Draws the app icon and writes every macOS size into an asset catalog's AppIcon.appiconset.
//
//   swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
//
// Flat, layered shapes on a dark rounded square: an orange status light sending out signal arcs. Each size is
// drawn from the vector shapes rather than scaled down.
import AppKit

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func pill(_ ctx: CGContext, _ rect: CGRect, _ fill: CGColor) {
    let radius = min(rect.width, rect.height) / 2
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(fill)
    ctx.fillPath()
}

func disc(_ ctx: CGContext, _ center: CGPoint, _ radius: CGFloat, _ fill: CGColor) {
    ctx.setFillColor(fill)
    ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

// Apple's macOS icon grid: an 824-point body centered on the 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

let orange: UInt32 = 0xFF6E40

/// An orange status light sending out signal arcs, with a long shadow.
func drawBeacon(_ ctx: CGContext) {
    let center = CGPoint(x: 512, y: 440)

    // The long shadow, down and to the right, as wide as the light.
    let reach: CGFloat = 700
    let shadow = CGMutablePath()
    shadow.move(to: CGPoint(x: center.x - 85, y: center.y + 85))
    shadow.addLine(to: CGPoint(x: center.x - 85 + reach, y: center.y + 85 - reach))
    shadow.addLine(to: CGPoint(x: center.x + 85 + reach, y: center.y - 85 - reach))
    shadow.addLine(to: CGPoint(x: center.x + 85, y: center.y - 85))
    shadow.closeSubpath()
    ctx.addPath(shadow)
    ctx.setFillColor(color(0x000000, 0.22))
    ctx.fillPath()

    // Signal arcs above the light, fading outwards.
    ctx.setLineCap(.round)
    for (i, radius) in [210, 300, 390].enumerated() {
        ctx.setStrokeColor(color(orange, [1, 0.7, 0.42][i]))
        ctx.setLineWidth(46)
        ctx.addArc(
            center: center, radius: CGFloat(radius), startAngle: .pi * 0.25, endAngle: .pi * 0.75, clockwise: false)
        ctx.strokePath()
    }

    // The light: rings of orange around a white center.
    disc(ctx, center, 128, color(0xE64A19))
    disc(ctx, center, 100, color(orange))
    disc(ctx, center, 62, color(0xFFAB91))
    disc(ctx, center, 30, color(0xFFFFFF))

    // A small stand under it.
    pill(ctx, CGRect(x: center.x - 110, y: center.y - 200, width: 220, height: 40), color(0x546E7A))
}

/// Draws the icon on a 1024-point canvas (the context is scaled to the output size).
func draw(_ ctx: CGContext) {
    // A soft shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x263238))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let background = CGGradient(
        colorsSpace: space, colors: [color(0x37474F), color(0x1C262B)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        background, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
    drawBeacon(ctx)
    ctx.restoreGState()
}

func png(pixels: Int) -> Data {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: swift scripts/make-icon.swift <AppIcon.appiconset>\n".data(using: .utf8)!)
    exit(2)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(pixels: points * scale).write(to: folder.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: folder.appendingPathComponent("Contents.json"))
