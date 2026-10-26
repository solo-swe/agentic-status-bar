import ASBCore
import Foundation
import Observation
import ServiceManagement

/// What LoginItem needs from SMAppService (tests use a fake).
protocol LoginService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginService {}

/// "Start at login": the app as its own login item (SMAppService.mainApp). Turning it on also
/// removes the SwiftBar era's LaunchAgent, which started SwiftBar at login.
@MainActor
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status
    private(set) var failure: String?

    @ObservationIgnored private let service: LoginService
    @ObservationIgnored private let oldLaunchAgent: String

    init(
        service: LoginService = SMAppService.mainApp,
        oldLaunchAgent: String = Paths.from(environment: ProcessInfo.processInfo.environment).loginItemFile
    ) {
        self.service = service
        self.oldLaunchAgent = oldLaunchAgent
        status = service.status
    }

    /// On, or waiting for the user's approval in System Settings.
    var enabled: Bool { status == .enabled || status == .requiresApproval }

    var needsApproval: Bool { status == .requiresApproval }

    func set(_ on: Bool) {
        do {
            if on {
                try service.register()
                try? FileManager.default.removeItem(atPath: oldLaunchAgent)
            } else {
                try service.unregister()
            }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        refresh()
    }

    /// The status can change in System Settings while the app runs.
    func refresh() {
        status = service.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
