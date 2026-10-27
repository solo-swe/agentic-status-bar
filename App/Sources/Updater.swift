import Foundation
import Sparkle

/// Updates through Sparkle, from the appcast attached to the latest GitHub release.
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController

    init(bundle: Bundle = .main) {
        controller = SPUStandardUpdaterController(
            startingUpdater: Self.canUpdate(bundle.infoDictionary ?? [:]), updaterDelegate: nil,
            userDriverDelegate: nil)
    }

    /// Whether this build can update itself: it needs the feed and the public key that release builds carry.
    /// Unit tests host the app, and stay quiet.
    static func canUpdate(_ info: [String: Any], environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard environment["XCTestConfigurationFilePath"] == nil else { return false }
        let key = info["SUPublicEDKey"] as? String ?? ""
        let feed = info["SUFeedURL"] as? String ?? ""
        return !key.isEmpty && !feed.isEmpty
    }

    /// False in builds without a key (local builds) and while a check is running.
    var canCheck: Bool { controller.updater.canCheckForUpdates }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
