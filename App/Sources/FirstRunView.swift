import AppKit
import SwiftUI

/// The first-run window: what installing the hooks changes, and a button to do it.
struct FirstRunView: View {
    let hooks: HookInstaller
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkle").font(.largeTitle).foregroundStyle(.tint)
                Text("Set up Agentic Status Bar").font(.title2.bold())
            }
            if hooks.installed {
                Text("The hooks are installed.")
                Text(Self.restartNote).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                }
            } else {
                Text("To see your Claude Code sessions, the app adds hooks to Claude Code. This will:")
                VStack(alignment: .leading, spacing: 6) {
                    Label("Back up \(Self.tilde(hooks.settingsFile)), then add one hook per event to it. Your other settings and hooks stay as they are.", systemImage: "doc.badge.gearshape")
                    Label("Copy the app's asb tool to \(Self.tilde(hooks.installer().stableBinary)) for the hooks to run.", systemImage: "terminal")
                }
                .fixedSize(horizontal: false, vertical: true)
                Text("You can remove the hooks any time in Settings.").foregroundStyle(.secondary)
                if let failure = hooks.failure {
                    Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Not Now", action: close).keyboardShortcut(.cancelAction)
                    Button("Install Hooks") { hooks.install() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    static let restartNote = "Claude Code sessions that are already running pick up the hooks when they restart."

    /// A path with the home folder written as ~.
    static func tilde(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// Shows the first-run window on launch while the hooks aren't installed, unless the user chose
/// "Not Now" before (Settings can still install them).
@MainActor
final class FirstRunWindow {
    static let dismissedKey = "firstRunDismissed"
    private let hooks: HookInstaller
    private var window: NSWindow?

    init(hooks: HookInstaller) {
        self.hooks = hooks
    }

    func showIfNeeded() {
        guard !hooks.installed, !UserDefaults.standard.bool(forKey: Self.dismissedKey) else { return }
        let window = NSWindow(contentViewController: NSHostingController(rootView: FirstRunView(hooks: hooks) { [weak self] in
            self?.close()
        }))
        window.title = "Agentic Status Bar"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        if !hooks.installed { UserDefaults.standard.set(true, forKey: Self.dismissedKey) }
        window?.close()
    }
}
