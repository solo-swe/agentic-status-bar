import ASBCore
import SwiftUI

/// The Settings window. Every control reads and writes the config file the CLI uses, so the app,
/// `asb` and the SwiftBar plugin stay in sync.
struct SettingsView: View {
    let store: SessionStore

    var body: some View {
        Form {
            Section("Sessions to show") {
                toggle("Interactive sessions", "show_interactive", \.showInteractive)
                toggle("Headless sessions (claude -p)", "show_headless", \.showHeadless)
                toggle("IDE sessions", "show_ide", \.showIDE)
                toggle("Subagent rows", "show_subagents", \.showSubagents)
            }
            Section("Activity") {
                Picker("Busy with no activity counts as uncertain after", selection: Binding(
                    get: { store.config.staleMinutes },
                    set: { store.set("stale_minutes", String($0)) })
                ) {
                    ForEach(Self.staleChoices, id: \.minutes) { Text($0.label).tag($0.minutes) }
                }
                toggle("Find sessions in Claude Code's registry", "use_registry", \.useRegistry)
                toggle("Refresh the menu bar on every hook event", "instant_refresh", \.instantRefresh)
                toggle("Store prompt previews as row titles", "store_prompt_preview", \.storePromptPreview)
            }
            Section("Appearance") {
                Picker("Theme", selection: Binding(get: { store.config.theme }, set: { store.set("theme", $0) })) {
                    ForEach(Self.themes, id: \.self) { Text(Self.themeName($0)).tag($0) }
                }
                let theme = Theme.resolve(store.config)
                ForEach(Config.themeStates, id: \.self) { state in
                    StateOverrideRow(
                        state: state, symbol: theme.symbol(state), color: theme.color(state),
                        overridden: store.config.iconOverrides[state] != nil || store.config.colorOverrides[state] != nil,
                        set: { key, value in store.set("\(key)_\(state)", value) })
                }
            }
            Section {
                Button("Reveal config file") { store.perform("reveal-config", []) }
            } footer: {
                Text(store.paths.configFile).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 480)
    }

    private func toggle(_ title: String, _ key: String, _ value: KeyPath<Config, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { store.config[keyPath: value] }, set: { store.set(key, $0) }))
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

/// One state's symbol and colors: a symbol name field with a preview, and a light and a dark color.
struct StateOverrideRow: View {
    let state: String
    let symbol: String
    let color: String
    let overridden: Bool
    /// Writes `icon` or `color` for this state; "" removes the override.
    let set: (String, String) -> Void

    @State private var text = ""
    @State private var editing = false

    var body: some View {
        let halves = ThemeColor.halves(color)
        HStack(spacing: 8) {
            Text(SettingsView.stateName(state)).frame(width: 150, alignment: .leading)
            Image(systemName: NSImage(systemSymbolName: shownSymbol, accessibilityDescription: nil) != nil
                  ? shownSymbol : "questionmark.square.dashed")
                .foregroundStyle(ThemeColor.color(color).map(Color.init(nsColor:)) ?? .primary)
                .frame(width: 20)
            TextField("SF Symbol", text: $text, onEditingChanged: { editing = $0 })
                .labelsHidden()
                .foregroundStyle(Self.isSymbol(text) ? .primary : Color.red)
                .onSubmit(commitSymbol)
            ColorPicker("Light", selection: colorBinding(halves, dark: false), supportsOpacity: false)
                .labelsHidden()
                .help("Color in a light menu bar")
            ColorPicker("Dark", selection: colorBinding(halves, dark: true), supportsOpacity: false)
                .labelsHidden()
                .help("Color in a dark menu bar")
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
        .onAppear { text = symbol }
        .onChange(of: symbol) { if !editing { text = symbol } }
    }

    private var shownSymbol: String { Self.isSymbol(text) ? text : symbol }

    static func isSymbol(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private func commitSymbol() {
        let name = text.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { set("icon", "") } else if Self.isSymbol(name), name != symbol { set("icon", name) }
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
