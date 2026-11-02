import ASBCore
import Foundation
import Observation

/// The app's side of `asb install`: whether the hooks are installed, installing them with the asb
/// bundled in Contents/Helpers, removing them, and keeping the stable copy the hooks run up to date.
@MainActor
@Observable
final class HookInstaller {
    private(set) var installed = false
    /// The last install or uninstall error, for the UI.
    private(set) var failure: String?

    @ObservationIgnored private let environment: [String: String]
    @ObservationIgnored private let bundledAsb: String

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundledAsb: String = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/asb").path
    ) {
        self.environment = environment
        self.bundledAsb = bundledAsb
        installed = installer().hooksInstalled
    }

    /// An installer for this machine, as `asb install` builds one, except that an old SwiftBar link
    /// is left to `asb install`.
    func installer() -> Installer {
        var installer = Installer.forMachine(environment: environment, sourceBinary: bundledAsb, swiftBarDir: nil)
        installer.log = { _ in }
        return installer
    }

    /// The settings file the hooks go into, for the UI.
    var settingsFile: String { installer().settingsFile }

    /// At launch, brings an existing install up to date: hooks installed before an event was added are
    /// reinstalled (which also copies asb); otherwise an outdated stable copy, the asb the hooks run, is
    /// replaced with the bundled one. Does nothing when the hooks aren't installed.
    func bringUpToDate() {
        let installer = installer()
        guard FileManager.default.fileExists(atPath: bundledAsb) else { return }
        if installer.hooksOutdated {
            try? installer.install()
            installed = installer.hooksInstalled
            return
        }
        guard installer.hooksInstalled, !installer.binaryIsCurrent else { return }
        try? installer.updateBinary()
    }

    func install() {
        run { try $0.install() }
    }

    func uninstall() {
        run { try $0.uninstall(purge: false) }
    }

    private func run(_ change: (Installer) throws -> Void) {
        let installer = installer()
        do {
            try change(installer)
            failure = nil
        } catch Installer.Failure.invalidSettings(let file) {
            failure = "\(file) isn't valid JSON, so it was left as it is."
        } catch {
            failure = error.localizedDescription
        }
        installed = installer.hooksInstalled
    }
}
