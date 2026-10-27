import AppKit

/// The standard About panel, with the app's version and build and a link to the project.
@MainActor
enum AboutPanel {
    static let projectURL = URL(string: "https://github.com/solo-swe/agentic-status-bar")!

    /// Opens the panel; a menu-bar app has to activate itself first, or the panel opens behind other windows.
    static func show() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: options(Bundle.main))
    }

    /// The panel's options. The name, icon and copyright come from the bundle as well; they are passed
    /// explicitly so the panel doesn't depend on which keys AppKit falls back to.
    static func options(_ bundle: Bundle) -> [NSApplication.AboutPanelOptionKey: Any] {
        let info = bundle.infoDictionary ?? [:]
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: info["CFBundleName"] as? String ?? "Agentic Status Bar",
            .credits: credits(),
        ]
        if let version = info["CFBundleShortVersionString"] as? String { options[.applicationVersion] = version }
        if let build = info["CFBundleVersion"] as? String { options[.version] = build }
        if let icon = NSApp?.applicationIconImage { options[.applicationIcon] = icon }
        return options
    }

    /// One centered line: what the app is, and a link to its repository.
    static func credits() -> NSAttributedString {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: center,
        ]
        let text = NSMutableAttributedString(string: "Your Claude Code sessions in the menu bar.\n", attributes: base)
        var link = base
        link[.link] = projectURL
        text.append(NSAttributedString(string: "github.com/solo-swe/agentic-status-bar", attributes: link))
        return text
    }
}
