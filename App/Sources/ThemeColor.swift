import AppKit

/// Theme colors: `#RRGGBB` or a `#RRGGBB,#RRGGBB` light,dark pair (doc/snapshot-schema.md).
enum ThemeColor {
    /// A dynamic color that follows the appearance it is drawn in; nil for anything else.
    static func color(_ spec: String) -> NSColor? {
        guard let (light, dark) = halves(spec) else { return nil }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static func hex(_ text: String) -> NSColor? {
        let digits = text.trimmingCharacters(in: .whitespaces)
        guard digits.count == 7, digits.first == "#", let value = UInt32(digits.dropFirst(), radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// `#RRGGBB` in sRGB; nil for a color that has no sRGB form (a pattern, say).
    static func hexString(_ color: NSColor) -> String? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }

    /// The light and dark halves of a color setting (a single color is both).
    static func halves(_ spec: String) -> (light: NSColor, dark: NSColor)? {
        let parts = spec.split(separator: ",").map(String.init)
        guard (1...2).contains(parts.count), let light = hex(parts[0]), let dark = hex(parts.last ?? parts[0]) else { return nil }
        return (light, dark)
    }

    /// An SF Symbol drawn in `color` (not a template, so the menu bar keeps the color).
    static func symbol(_ name: String, color: NSColor?, pointSize: CGFloat = 14) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: name) else { return nil }
        var config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        if let color { config = config.applying(.init(paletteColors: [color])) }
        let image = base.withSymbolConfiguration(config)
        image?.isTemplate = color == nil
        return image
    }
}
