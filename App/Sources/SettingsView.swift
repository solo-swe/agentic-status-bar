import ASBCore
import SwiftUI

/// The Settings window: a General and an Appearance tab. Every control reads and writes the config
/// file the CLI uses, so the app, `asb` and the SwiftBar plugin stay in sync.
struct SettingsView: View {
    let store: SessionStore

    var body: some View {
        TabView {
            GeneralSettings(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings(store: store)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The stale threshold choices; the same values `asb action set stale_minutes` accepts.
    static let staleChoices: [(minutes: Int, label: String)] = [
        (10, "10 minutes"), (30, "30 minutes"), (60, "1 hour"), (0, "Never"),
    ]

    static let themes = ["default", "monochrome", "high_contrast"]

    static func themeName(_ id: String) -> String {
        switch id {
        case "high_contrast": "High contrast"
        default: id.prefix(1).uppercased() + id.dropFirst()
        }
    }

    static func stateName(_ state: String) -> String {
        switch state {
        case "uncertain": "No activity"
        case "subagents": "Waiting on subagents"
        case "none": "No sessions"
        case "busy": "Working"
        default: state.prefix(1).uppercased() + state.dropFirst()
        }
    }

    /// The `color_<state>` value for a light and a dark color.
    static func colorSetting(light: NSColor, dark: NSColor) -> String? {
        guard let l = ThemeColor.hexString(light), let d = ThemeColor.hexString(dark) else { return nil }
        return "\(l),\(d)"
    }
}

/// Which sessions to show, and when a quiet one counts as uncertain.
private struct GeneralSettings: View {
    let store: SessionStore

    var body: some View {
        Form {
            Section("Show") {
                toggle("Interactive sessions", "show_interactive", \.showInteractive)
                toggle("Headless sessions (claude -p)", "show_headless", \.showHeadless)
                toggle("IDE sessions", "show_ide", \.showIDE)
                toggle("Subagents under their session", "show_subagents", \.showSubagents)
            }
            Section("Activity") {
                Picker("Mark as \u{201C}no activity\u{201D} after", selection: Binding(
                    get: { store.config.staleMinutes },
                    set: { store.set("stale_minutes", String($0)) })
                ) {
                    ForEach(SettingsView.staleChoices, id: \.minutes) { Text($0.label).tag($0.minutes) }
                }
                toggle("Find sessions in Claude Code's registry", "use_registry", \.useRegistry)
                toggle("Update the menu bar on every hook event", "instant_refresh", \.instantRefresh)
                toggle("Use the first prompt as a session's title", "store_prompt_preview", \.storePromptPreview)
            }
            Section {
                LabeledContent("Config file") {
                    Button("Show in Finder") { store.perform("reveal-config", []) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func toggle(_ title: String, _ key: String, _ value: KeyPath<Config, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { store.config[keyPath: value] }, set: { store.set(key, $0) }))
    }
}

/// The theme, and each state's symbol and colors.
private struct AppearanceSettings: View {
    let store: SessionStore

    var body: some View {
        let theme = Theme.resolve(store.config)
        Form {
            Picker("Theme", selection: Binding(get: { store.config.theme }, set: { store.set("theme", $0) })) {
                ForEach(SettingsView.themes, id: \.self) { Text(SettingsView.themeName($0)).tag($0) }
            }
            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("State")
                        Text("Symbol").gridColumnAlignment(.center)
                        Text("Light menu bar").gridColumnAlignment(.center)
                        Text("Dark menu bar").gridColumnAlignment(.center)
                        Color.clear.frame(width: 1, height: 1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(Config.themeStates, id: \.self) { state in
                        StateOverrideRow(
                            state: state, symbol: theme.symbol(state), color: theme.color(state),
                            overridden: store.config.iconOverrides[state] != nil
                                || store.config.colorOverrides[state] != nil,
                            set: { key, value in store.set("\(key)_\(state)", value) })
                    }
                }
            } footer: {
                Text("Click a symbol to change it. ↩︎ goes back to the theme's symbol and colors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// One state's grid row: its symbol (click to edit the name), its light and dark colors, and reset.
struct StateOverrideRow: View {
    let state: String
    let symbol: String
    let color: String
    let overridden: Bool
    /// Writes `icon` or `color` for this state; "" removes the override.
    let set: (String, String) -> Void

    @State private var editing = false

    var body: some View {
        let halves = ThemeColor.halves(color)
        GridRow {
            Text(SettingsView.stateName(state))
            Button {
                editing = true
            } label: {
                Image(systemName: Self.isSymbol(symbol) ? symbol : "questionmark.square.dashed")
                    .foregroundStyle(ThemeColor.color(color).map(Color.init(nsColor:)) ?? .primary)
                    .frame(width: 28, height: 20)
            }
            .buttonStyle(.bordered)
            .help(symbol)
            .popover(isPresented: $editing, arrowEdge: .bottom) {
                SymbolEditor(symbol: symbol) { set("icon", $0) }
            }
            ColorPicker("Light menu bar", selection: colorBinding(halves, dark: false), supportsOpacity: false)
                .labelsHidden()
            ColorPicker("Dark menu bar", selection: colorBinding(halves, dark: true), supportsOpacity: false)
                .labelsHidden()
            Button {
                set("icon", "")
                set("color", "")
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Use the theme's symbol and colors")
            .opacity(overridden ? 1 : 0)
            .disabled(!overridden)
        }
    }

    static func isSymbol(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private func colorBinding(_ halves: (light: NSColor, dark: NSColor)?, dark: Bool) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: (dark ? halves?.dark : halves?.light) ?? .labelColor) },
            set: { picked in
                let new = NSColor(picked)
                let light = dark ? halves?.light ?? new : new
                let darkColor = dark ? new : halves?.dark ?? new
                if let value = SettingsView.colorSetting(light: light, dark: darkColor), value != color {
                    set("color", value)
                }
            })
    }
}

/// The popover for a symbol's name, with a live preview; Return applies it.
private struct SymbolEditor: View {
    let symbol: String
    let apply: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let valid = StateOverrideRow.isSymbol(text)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: valid ? text : "questionmark.square.dashed")
                    .font(.title2)
                    .frame(width: 32)
                TextField("SF Symbol name", text: $text)
                    .frame(width: 200)
                    .onSubmit {
                        guard valid else { return }
                        if text != symbol { apply(text) }
                        dismiss()
                    }
            }
            Text(valid || text.isEmpty ? "Names are listed in Apple's SF Symbols app." : "No symbol with this name.")
                .font(.caption)
                .foregroundStyle(valid || text.isEmpty ? Color.secondary : Color.red)
        }
        .padding(12)
        .onAppear { text = symbol }
    }
}
