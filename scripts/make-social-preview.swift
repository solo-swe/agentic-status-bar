// Draws the repository's social preview (1280×640, shown when the repository is linked) to a PNG.
//
//   swift scripts/make-social-preview.swift doc/social-preview.png
//
// Upload it in the repository's Settings › General › Social preview; GitHub has no API for that.
// The session list uses made-up projects and the default theme's light-mode colors.
import AppKit

let width: CGFloat = 1280
let height: CGFloat = 640

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A rectangle given from the top-left corner, as the layout below is written.
func box(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: height - top - h, width: w, height: h)
}

func text(_ string: String, _ rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor,
          mono: Bool = false, align: NSTextAlignment = .left, wrap: Bool = false) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
}

/// A `.fill` symbol gets its mark in white over the color, as the menu bar shows it.
func symbol(_ name: String, _ rect: NSRect, color: NSColor, size: CGFloat) {
    let palette = name.hasSuffix(".fill") ? [NSColor.white, color] : [color]
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        .applying(.init(paletteColors: palette))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    else { return }
    // Centered in rect, at its own aspect ratio.
    let s = image.size
    let origin = NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2)
    image.draw(in: NSRect(origin: origin, size: s))
}

func rounded(_ rect: NSRect, _ radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func draw(icon: NSImage?) {
    // Background: the icon's white, with a faint orange glow behind the list.
    NSGradient(colors: [color(0xFFFFFF), color(0xEEF1F3)])?.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)
    NSGradient(colors: [color(0xFF6E40, 0.16), color(0xFF6E40, 0)])?
        .draw(fromCenter: NSPoint(x: 960, y: 330), radius: 0, toCenter: NSPoint(x: 960, y: 330), radius: 420, options: [])

    // Left: the icon, the name, what it does, how to install it.
    icon?.draw(in: box(72, 64, 190, 190))
    text("Agentic Status Bar", box(84, 276, 600, 80), size: 60, weight: .bold, color: color(0x1D1D1F))
    text("Know at a glance when your Claude Code agents need you.", box(86, 360, 540, 90), size: 30,
         color: color(0x515154), wrap: true)
    rounded(box(84, 486, 580, 54), 12, fill: color(0x1D1D1F))
    text("brew install --cask solo-swe/tap/agentic-status-bar", box(106, 500, 550, 30), size: 17, weight: .medium,
         color: color(0xF5F5F7), mono: true)
    text("Free and open source · macOS 14+ · Apple silicon", box(86, 562, 560, 30), size: 18, color: color(0x86868B))

    // Right: a menu bar with the status item, and its session list.
    let left: CGFloat = 690
    let w: CGFloat = 520
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.18)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -10)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    rounded(box(left, 70, w, 46), 12, fill: color(0xF5F5F7, 0.96))
    NSGraphicsContext.restoreGraphicsState()
    text("10:42", box(left + w - 70, 82, 56, 24), size: 16, weight: .medium, color: color(0x1D1D1F), align: .right)
    symbol("battery.75percent", box(left + w - 120, 78, 40, 30), color: color(0x1D1D1F), size: 17)
    symbol("wifi", box(left + w - 158, 78, 30, 30), color: color(0x1D1D1F), size: 16)
    // The status item: one waiting session, highlighted as when its list is open.
    let item = box(left + w - 246, 76, 70, 34)
    rounded(item, 8, fill: color(0x000000, 0.08))
    symbol("exclamationmark.circle.fill", box(item.minX + 8, 80, 26, 26), color: color(0xD70015), size: 17)
    text("1", box(item.minX + 38, 81, 24, 24), size: 17, weight: .semibold, color: color(0xD70015))

    // The popover, its arrow under the status item.
    let card = box(left, 132, w, 352)
    let path = NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18)
    let tip = NSPoint(x: item.midX, y: card.maxY + 14)
    path.move(to: NSPoint(x: tip.x - 16, y: card.maxY - 1))
    path.line(to: tip)
    path.line(to: NSPoint(x: tip.x + 16, y: card.maxY - 1))
    path.close()
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color(0xFFFFFF).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    let rows: [(symbol: String, color: UInt32, title: String, word: String, time: String)] = [
        ("exclamationmark.circle.fill", 0xD70015, "api-gateway — Add rate limiting", "permission", "2m"),
        ("zzz", 0xB25000, "web-dashboard — Fix flaky login test", "idle", "14m"),
        ("questionmark.circle", 0x8E8E93, "data-pipeline — Refactor CSV parser", "no activity", "41m"),
        ("sparkle", 0x6E6E73, "docs-site — New docs theme", "working", "30s"),
        ("hourglass", 0x6E6E73, "search-index — Rebuild the ranking", "2 subagents", "3m"),
    ]
    for (i, row) in rows.enumerated() {
        let top = 154 + CGFloat(i) * 52
        if i == 0 { rounded(box(left + 12, top - 6, w - 24, 46), 10, fill: color(0xD70015, 0.07)) }
        symbol(row.symbol, box(left + 22, top, 30, 34), color: color(row.color), size: 18)
        text(row.title, box(left + 60, top + 6, 290, 26), size: 18, color: color(0x1D1D1F))
        text(row.word, box(left + 330, top + 6, 120, 26), size: 17, color: color(0x86868B), align: .right)
        text(row.time, box(left + 456, top + 6, 44, 26), size: 17, color: color(0x86868B), align: .right)
    }
    color(0xE5E5EA).setFill()
    NSBezierPath(rect: box(left + 20, 418, w - 40, 1)).fill()
    text("Quit", box(left + 24, 438, 80, 26), size: 17, color: color(0x86868B))
    for (i, name) in ["questionmark.circle", "info.circle", "gearshape"].enumerated() {
        symbol(name, box(left + w - 112 + CGFloat(i) * 34, 434, 30, 30), color: color(0x86868B), size: 17)
    }
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: swift scripts/make-social-preview.swift <output.png>\n".data(using: .utf8)!)
    exit(2)
}
let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let icon = NSImage(contentsOf: here.appendingPathComponent(
    "../App/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"))

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { draw(icon: icon) }
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
