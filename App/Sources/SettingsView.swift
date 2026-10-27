import ASBCore
import SwiftUI

/// What the Settings tabs share. The tabs themselves (General, Appearance, Notifications) are hosted by
/// `SettingsWindow`; every control reads and writes the config file the CLI uses, so the app and `asb` agree.
enum SettingsView {
    /// The width of every tab; each tab's height follows its content.
    static let width: CGFloat = 500

    /// The stale threshold choices; the same values `asb action set stale_minutes` accepts.
    static let staleChoices: [(minutes: Int, label: String)] = [
        (10, "10 minutes"), (30, "30 minutes"), (60, "1 hour"), (0, "Never"),
    ]

    static let themes = ["default", "monochrome", "high_contrast"]

    /// The notification delays offered, in seconds.
    static let delayChoices = [5, 10, 30, 60]

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

/// Starting at login, the hooks, which sessions to show, and when a quiet one counts as uncertain.
struct GeneralSettings: View {
    let store: SessionStore
    let hooks: HookInstaller
    let login: LoginItem
    @State private var confirmingRemove = false

    var body: some View {
        Form {
            Section {
                Toggle("Start at login", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
                if login.needsApproval {
                    LabeledContent("Needs your approval in Login Items") {
                        Button("Open Login Items") { login.openSystemSettings() }
                    }
                    .foregroundStyle(.secondary)
                }
                if let failure = login.failure { Text(failure).foregroundStyle(.red) }
            }
            .onAppear { login.refresh() }
            Section {
                LabeledContent {
                    if hooks.installed {
                        Button("Remove…") { confirmingRemove = true }
                    } else {
                        Button("Install") { hooks.install() }
                    }
                } label: {
                    Label {
                        Text("Claude Code hooks")
                        Text(hooks.installed ? "Installed in \(FirstRunView.tilde(hooks.settingsFile))"
                             : "Not installed: no sessions will show up")
                    } icon: {
                        Image(systemName: hooks.installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hooks.installed ? .green : .orange)
                    }
                }
                if let failure = hooks.failure { Text(failure).foregroundStyle(.red) }
            }
            .confirmationDialog("Remove the hooks?", isPresented: $confirmingRemove) {
                Button("Remove Hooks", role: .destructive) { hooks.uninstall() }
            } message: {
                Text("Claude Code stops reporting sessions to the app. Your settings are backed up first; state and config files are kept.")
            }
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
                toggle("Use the first prompt as a session's title", "store_prompt_preview", \.storePromptPreview)
            }
            Section {
                LabeledContent("Config file") {
                    Button("Show in Finder") { store.perform("reveal-config", []) }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private func toggle(_ title: String, _ key: String, _ value: KeyPath<Config, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { store.config[keyPath: value] }, set: { store.set(key, $0) }))
    }
}

/// When the app notifies, and a test button.
struct NotificationSettings: View {
    let store: SessionStore
    let notifier: Notifier

    var body: some View {
        Form {
            Section {
                toggle("When a session is waiting on you", "notify_waiting", \.notifyWaiting)
                toggle("When a session finishes and goes idle", "notify_idle", \.notifyIdle)
                Picker("Notify after", selection: Binding(
                    get: { store.config.notifyDelaySeconds },
                    set: { store.set("notify_delay_seconds", String($0)) })
                ) {
                    ForEach(SettingsView.delayChoices, id: \.self) { Text("\($0) seconds").tag($0) }
                }
                toggle("Play a sound", "notify_sound", \.notifySound)
            } footer: {
                Text("Waiting notifications also come from muted projects; idle ones don't.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    Button("Send Test") { notifier.sendTest() }
                } label: {
                    Text("Test notification")
                    Text("None arriving? Check System Settings › Notifications")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private func toggle(_ title: String, _ key: String, _ value: KeyPath<Config, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { store.config[keyPath: value] }, set: { store.set(key, $0) }))
    }
}

/// The theme, and each state's symbol and colors.
struct AppearanceSettings: View {
    let store: SessionStore

    var body: some View {
        let theme = Theme.resolve(store.config)
        Form {
            Section {
                Picker("Theme", selection: Binding(get: { store.config.theme }, set: { store.set("theme", $0) })) {
                    ForEach(SettingsView.themes, id: \.self) { Text(SettingsView.themeName($0)).tag($0) }
                }
            }
            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("State")
                        Text("Symbol").gridColumnAlignment(.center)
                        Text("Color").gridColumnAlignment(.center)
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
            } header: {
                Text("Menu bar symbols")
            } footer: {
                Text("Click a symbol or a color to change it; each color has a shade for a light and a dark menu bar. ↩︎ goes back to the theme.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

/// One state's grid row: its symbol and its color (each opens a picker), and reset.
struct StateOverrideRow: View {
    let state: String
    let symbol: String
    let color: String
    let overridden: Bool
    /// Writes `icon` or `color` for this state; "" removes the override.
    let set: (String, String) -> Void

    @State private var pickingSymbol = false
    @State private var pickingColor = false

    var body: some View {
        let tint = ThemeColor.color(color).map(Color.init(nsColor:)) ?? .primary
        GridRow {
            Text(SettingsView.stateName(state))
            Button {
                pickingSymbol = true
            } label: {
                Image(systemName: Self.isSymbol(symbol) ? symbol : "questionmark.square.dashed")
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 20)
            }
            .buttonStyle(.bordered)
            .help("Change the symbol")
            .popover(isPresented: $pickingSymbol, arrowEdge: .bottom) {
                SymbolPicker(selected: symbol, color: tint) { name in
                    if name != symbol { set("icon", name) }
                    pickingSymbol = false
                }
            }
            Button {
                pickingColor = true
            } label: {
                ColorSwatch(value: color)
            }
            .buttonStyle(.plain)
            .help("Change the color")
            .popover(isPresented: $pickingColor, arrowEdge: .bottom) {
                ColorPalette(selected: color) { value in
                    if value != color { set("color", value) }
                    pickingColor = false
                }
            }
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
}
