import SwiftUI

/// The symbols and colors the Appearance tab offers for a state.
enum SymbolChoices {
    /// SF Symbols that read well as a menu-bar status: every built-in theme's symbols, and alternatives.
    static let symbols = [
        "exclamationmark.circle.fill", "exclamationmark.circle", "exclamationmark.triangle.fill",
        "exclamationmark.triangle", "exclamationmark.octagon.fill", "exclamationmark.bubble.fill",
        "hand.raised.fill", "bell.fill", "bell.badge.fill",
        "bell", "bell.slash", "bell.slash.fill", "questionmark.circle", "questionmark.circle.fill",
        "ellipsis.circle", "zzz", "moon.zzz.fill", "moon.fill",
        "moon", "pause.circle.fill", "pause.circle", "checkmark.circle.fill", "checkmark.circle", "cup.and.saucer.fill",
        "sparkle", "sparkles", "star.fill",
        "bolt.fill", "bolt.circle.fill", "flame.fill", "hare.fill", "tortoise.fill", "cpu",
        "hourglass", "hourglass.circle.fill", "clock.fill",
        "circle.fill", "circle", "circle.dotted", "smallcircle.filled.circle", "record.circle", "circle.hexagongrid.fill",
        "dot.radiowaves.left.and.right", "antenna.radiowaves.left.and.right", "waveform",
        "terminal", "terminal.fill", "bubble.left.fill", "text.bubble.fill", "person.2.fill", "eye.slash",
        "speaker.slash.fill", "xmark.circle.fill", "ellipsis",
    ]

    /// System colors as `light,dark` settings: the light half is Apple's higher-contrast variant, which
    /// stays readable on a light menu bar; the dark half is the standard dark-mode color.
    static let palette: [(name: String, value: String)] = [
        ("Red", "#D70015,#FF453A"), ("Orange", "#C93400,#FF9F0A"), ("Yellow", "#B25000,#FFD60A"),
        ("Green", "#248A3D,#30D158"), ("Mint", "#0C817B,#63E6E2"), ("Teal", "#008299,#40C8E0"),
        ("Blue", "#0040DD,#0A84FF"), ("Indigo", "#3634A3,#5E5CE6"), ("Purple", "#8944AB,#BF5AF2"),
        ("Pink", "#D30F45,#FF375F"), ("Brown", "#7F6545,#AC8E68"), ("Gray", "#6E6E73,#AEAEB2"),
        ("Light gray", "#8E8E93,#98989D"), ("Black and white", "#1D1D1F,#F5F5F7"),
    ]
}

/// A grid of symbols in the state's color; clicking one picks it.
struct SymbolPicker: View {
    let selected: String
    let color: Color
    let pick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 9), spacing: 4) {
            ForEach(SymbolChoices.symbols, id: \.self) { name in
                Button { pick(name) } label: {
                    Image(systemName: name)
                        .font(.system(size: 15))
                        .foregroundStyle(color)
                        .frame(width: 32, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(name == selected ? Color.accentColor.opacity(0.25) : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(name)
            }
        }
        .padding(10)
    }
}

/// Color swatches, each showing its light and dark halves; clicking one picks it.
struct ColorPalette: View {
    let selected: String
    let pick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 7), spacing: 6) {
            ForEach(SymbolChoices.palette, id: \.value) { choice in
                Button { pick(choice.value) } label: {
                    ColorSwatch(value: choice.value, selected: choice.value == selected)
                }
                .buttonStyle(.plain)
                .help(choice.name)
            }
        }
        .padding(10)
    }
}

/// A circle split diagonally: the color on a light menu bar (top left) and on a dark one (bottom right).
struct ColorSwatch: View {
    let value: String
    var selected = false

    var body: some View {
        let halves = ThemeColor.halves(value)
        ZStack {
            Circle().fill(Color(nsColor: halves?.dark ?? .labelColor))
            Circle()
                .fill(Color(nsColor: halves?.light ?? .labelColor))
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.5), .init(color: .clear, location: 0.5)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(Color.primary.opacity(0.15))
        }
        .frame(width: 22, height: 22)
        .padding(3)
        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(selected ? 1 : 0))
    }
}
