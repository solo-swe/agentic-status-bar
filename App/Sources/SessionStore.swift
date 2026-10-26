import ASBCore
import Foundation
import Observation

/// The current snapshot for the UI. Recomputed off the main thread when the state dir, the registry
/// or the config changes (coalesced to at most every 200 ms), and every 5 s for process liveness and
/// staleness. Dead sessions' files are deleted, as `asb snapshot` does.
@MainActor
@Observable
final class SessionStore {
    private(set) var snapshot: Snapshot?
    /// The settings the snapshot was computed with (the menu shows them).
    private(set) var config = Config()

    static let coalesceInterval: TimeInterval = 0.2
    static let refreshInterval: TimeInterval = 5

    @ObservationIgnored private let live: LiveInputs
    @ObservationIgnored private var coalescer: Coalescer?
    @ObservationIgnored private var watchers: [DirectoryWatcher] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var computing = false
    @ObservationIgnored private var again = false

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        live = LiveInputs(
            paths: Paths.from(environment: environment), environment: environment,
            inspector: ProcessInspectors.fromEnvironment(environment))
    }

    var paths: Paths { live.paths }

    func start() {
        let coalescer = Coalescer(interval: Self.coalesceInterval) { [weak self] in self?.recompute() }
        self.coalescer = coalescer
        watch()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { _ in
            MainActor.assumeIsolated { coalescer.trigger() }
        }
        coalescer.trigger()
    }

    /// Asks for a fresh snapshot soon (after an action changed something).
    func refresh() {
        coalescer?.trigger()
    }

    /// Runs a menu action (`asb action`'s names) off the main thread, then refreshes.
    func perform(_ name: String, _ args: [String]) {
        let (paths, environment) = (live.paths, live.environment)
        Task.detached(priority: .userInitiated) {
            Actions(paths: paths, environment: environment, runner: ProcessRunner(environment: environment))
                .perform(name, args)
            await MainActor.run { [weak self] in self?.refresh() }
        }
    }

    private func watch() {
        let config = Config.load(live.paths)
        let stateDir = live.paths.stateDir(config: config)
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        let dirs = [stateDir, live.paths.registryDir, (live.paths.configFile as NSString).deletingLastPathComponent]
        watchers = dirs.compactMap { dir in
            DirectoryWatcher(path: dir) { [weak self] in self?.coalescer?.trigger() }
        }
    }

    private func recompute() {
        // One computation at a time; a change during it causes one more.
        guard !computing else { again = true; return }
        computing = true
        let live = self.live
        Task.detached(priority: .utility) {
            let inputs = live.gather()
            let result = Engine.snapshot(inputs)
            live.apply(result, configText: inputs.configText)
            let config = Config.parse(inputs.configText)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.snapshot = result.snapshot
                self.config = config
                self.computing = false
                if self.again {
                    self.again = false
                    self.coalescer?.trigger()
                }
            }
        }
    }
}

/// Calls `onChange` (on the main actor) when entries are added, removed or renamed in a directory:
/// state files are written by renaming a temp file, so every write shows up.
@MainActor
final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject

    init?(path: String, onChange: @escaping @MainActor () -> Void) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { onChange() } }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
