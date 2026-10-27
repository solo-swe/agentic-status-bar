// Draws the app icon and writes every macOS size into an asset catalog's AppIcon.appiconset.
//
//   swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
//
// Flat, layered shapes on a dark rounded square: the menu bar with the app's status glyph, and the session list
// hanging from it. Each size is drawn from the vector shapes rather than scaled down.
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
let amber: UInt32 = 0xFFC107

/// A menu bar with the app's highlighted status glyph, and the session list hanging from it.
func drawPopover(_ ctx: CGContext) {
    // The menu bar, with two menu titles on the left.
    let bar = CGRect(x: body.minX, y: body.maxY - 140, width: body.width, height: 140)
    ctx.setFillColor(color(0x455A64))
    ctx.fill(bar)
    pill(ctx, CGRect(x: 190, y: bar.midY - 12, width: 96, height: 24), color(0xFFFFFF, 0.45))
    pill(ctx, CGRect(x: 312, y: bar.midY - 12, width: 72, height: 24), color(0xFFFFFF, 0.30))

    // The status glyph, highlighted as when its menu is open.
    let glyph = CGPoint(x: 752, y: bar.midY)
    pill(ctx, CGRect(x: glyph.x - 64, y: bar.midY - 44, width: 128, height: 88), color(0xFFFFFF, 0.18))
    disc(ctx, glyph, 30, color(orange))
    disc(ctx, glyph, 12, color(0xFFFFFF))

    // The popover: a card with an arrow pointing at the glyph, lifted with a shadow.
    let card = CGRect(x: 220, y: 170, width: 640, height: 560)
    let popover = CGMutablePath()
    popover.addRoundedRect(in: card, cornerWidth: 56, cornerHeight: 56)
    popover.move(to: CGPoint(x: glyph.x - 46, y: card.maxY - 1))
    popover.addLine(to: CGPoint(x: glyph.x, y: card.maxY + 50))
    popover.addLine(to: CGPoint(x: glyph.x + 46, y: card.maxY - 1))
    popover.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: color(0x000000, 0.5))
    ctx.addPath(popover)
    ctx.setFillColor(color(0xFAFAFA))
    ctx.fillPath()
    ctx.restoreGState()

    // Three sessions: waiting (highlighted), idle, busy.
    let rows: [(dot: UInt32, title: CGFloat, detail: CGFloat)] = [
        (orange, 330, 190), (amber, 280, 230), (0x90A4AE, 310, 160),
    ]
    let rowHeight: CGFloat = 168
    for (i, row) in rows.enumerated() {
        let midY = card.maxY - 112 - CGFloat(i) * rowHeight
        if i == 0 {
            let tint = CGRect(x: card.minX + 24, y: midY - 72, width: card.width - 48, height: 144)
            ctx.addPath(CGPath(roundedRect: tint, cornerWidth: 36, cornerHeight: 36, transform: nil))
            ctx.setFillColor(color(orange, 0.12))
            ctx.fillPath()
        } else {
            ctx.setFillColor(color(0xE0E0E0))
            ctx.fill(CGRect(x: card.minX + 48, y: midY + rowHeight / 2 - 2, width: card.width - 96, height: 4))
        }
        let dot = CGPoint(x: card.minX + 100, y: midY)
        disc(ctx, dot, 40, color(row.dot))
        if i == 0 {
            // "!" in the waiting dot.
            pill(ctx, CGRect(x: dot.x - 7, y: dot.y - 4, width: 14, height: 30), color(0xFFFFFF))
            disc(ctx, CGPoint(x: dot.x, y: dot.y - 18), 7.5, color(0xFFFFFF))
        }
        let textX = card.minX + 170
        pill(ctx, CGRect(x: textX, y: midY + 6, width: row.title, height: 32), color(0x37474F))
        pill(ctx, CGRect(x: textX, y: midY - 40, width: row.detail, height: 24), color(0xB0BEC5))
    }
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
    drawPopover(ctx)
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
    FileHandle.standardError.write(
        "usage: swift scripts/make-icon.swift <AppIcon.appiconset>\n".data(using: .utf8)!)
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
