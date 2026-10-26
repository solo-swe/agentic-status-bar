/// An SF Symbol and a light,dark color pair for each menu-bar state.
public struct Theme: Equatable, Sendable {
    public var icons: [String: String]
    public var colors: [String: String]

    public func symbol(_ state: String) -> String { icons[state] ?? "" }
    public func color(_ state: String) -> String { colors[state] ?? "" }

    public static let builtIn: [String: Theme] = [
        "default": Theme(
            icons: [
                "waiting": "exclamationmark.circle.fill", "idle": "zzz", "uncertain": "questionmark.circle",
                "busy": "sparkle", "subagents": "hourglass", "muted": "bell.slash", "none": "sparkle",
                "warning": "exclamationmark.triangle",
            ],
            colors: [
                "waiting": "#D70015,#FF453A", "idle": "#B25000,#FFD60A", "uncertain": "#8E8E93,#98989D",
                "busy": "#6E6E73,#AEAEB2", "subagents": "#6E6E73,#AEAEB2", "muted": "#8E8E93,#98989D",
                "none": "#C7C7CC,#48484A", "warning": "#B25000,#FFD60A",
            ]),
        "monochrome": Theme(
            icons: [
                "waiting": "exclamationmark.circle.fill", "idle": "zzz", "uncertain": "questionmark.circle",
                "busy": "sparkle", "subagents": "hourglass", "muted": "bell.slash", "none": "sparkle",
                "warning": "exclamationmark.triangle",
            ],
            colors: [
                "waiting": "#1D1D1F,#F5F5F7", "idle": "#1D1D1F,#F5F5F7", "uncertain": "#6E6E73,#AEAEB2",
                "busy": "#6E6E73,#AEAEB2", "subagents": "#6E6E73,#AEAEB2", "muted": "#8E8E93,#98989D",
                "none": "#C7C7CC,#48484A", "warning": "#1D1D1F,#F5F5F7",
            ]),
        "high_contrast": Theme(
            icons: [
                "waiting": "exclamationmark.octagon.fill", "idle": "moon.zzz.fill",
                "uncertain": "questionmark.circle.fill", "busy": "bolt.fill", "subagents": "hourglass.circle.fill",
                "muted": "bell.slash.fill", "none": "circle.dotted", "warning": "exclamationmark.triangle.fill",
            ],
            colors: [
                "waiting": "#FF0000,#FF453A", "idle": "#C93400,#FFD60A", "uncertain": "#5856D6,#BF5AF2",
                "busy": "#000000,#FFFFFF", "subagents": "#000000,#FFFFFF", "muted": "#636366,#AEAEB2",
                "none": "#8E8E93,#636366", "warning": "#C93400,#FFD60A",
            ]),
    ]

    /// The theme the config asks for: the built-in theme (unknown names fall back to default), then
    /// the older `icon` key for the busy and empty icon, then the per-state overrides.
    public static func resolve(_ config: Config) -> Theme {
        var theme = builtIn[config.theme] ?? builtIn["default"]!
        if !config.icon.isEmpty {
            theme.icons["busy"] = config.icon
            theme.icons["none"] = config.icon
        }
        theme.icons.merge(config.iconOverrides) { _, override in override }
        theme.colors.merge(config.colorOverrides) { _, override in override }
        return theme
    }
}
