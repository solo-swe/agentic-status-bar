# Swift

Swift 6 with strict concurrency, for `ASBCore`, `asb` and the app. These are the rules the code follows; new code
follows them too.

## Layers

- `ASBCore` imports Foundation only. No AppKit, SwiftUI or `@MainActor` state: it has to stay testable without a UI
  and portable (`doc/design/future-architecture.md`).
- `asb` is a thin `ArgumentParser` front end over `ASBCore`. `Engine.snapshot`, `HookEvents.apply` and the checks do
  the work; commands read input, call them and write output.
- The app shows what the core computes. A rule the menu bar, the list or a notification depends on belongs in
  `ASBCore` or in a view model with its own tests, never in a view.

## Shape of the code

- **Pure functions on value types.** Logic is `static func` on a caseless `enum` used as a namespace (`HookEvents`,
  `Checks`, `ProcStart`) or methods on a `struct` (`StateFile`, `Config`, `Snapshot`). Input in, result out; the
  caller does the I/O.
- **Small types for what the data means**: `ReconciledSession`, `HookPayload`, `Snapshot.Session`. Prefer an `enum`
  with cases over strings and booleans when the set is closed (`HookEvents.Outcome`, `CompanionScene`).
- **Dependencies are injected**: the clock (`now`), the process table (`ProcessInspector`, with
  `FakeProcessInspector` and `ASB_PS_TABLE` for tests), file locations (`Paths`, `ASB_*` overrides), randomness
  (`random: () -> Double`), notification centers. Defaults are the real ones.
- **Time is epoch milliseconds (`Int64`)** in state, snapshots and checks. Local-time strings exist only where an
  outside format needs them (`procStart`, as `ps` prints it) and are compared as text, never parsed back.

## Errors and optionals

- No force unwraps or `try!` outside tests. `guard let … else { return }` for early exits.
- The hook and the background refresh never fail loudly: they use `try?` and carry on, because nothing can be shown
  to anyone there. Code with a caller who can act throws typed errors (`Installer.Failure`) and the UI says what
  happened.
- Untrusted input is parsed defensively: state files, payloads and registry files can be corrupt, partial or from a
  newer version. Parse to `nil` and count it (the warning state); never crash on input.

## Concurrency

- UI types are `@MainActor`; observable stores are `@MainActor @Observable final class`.
- Heavy work (`Engine.snapshot`) runs off the main thread and hands back a `Sendable` value.
- Value types are `Sendable` by construction. `nonisolated(unsafe)` only for immutable statics the compiler can't
  prove (a `[KeyPath]`), with the reason next to it. No `@unchecked Sendable` to silence a warning.
- Timers and observers are owned and invalidated; closures capture `[weak self]`.

## Style

- Names read as English at the call site: `Checks.liveness(sessions, processes:)`, `ProcStart.matches(text,
  seconds:)`.
- Comments say only what the code can't: a non-obvious reason or constraint, or the doc or PRD section a rule comes
  from (`doc/state-file-schema.md › Events`). No comment that repeats the name or the code below it. `public`
  declarations in `ASBCore` get `///` docs: what it does, its arguments, errors, an example where useful.
- Keep files focused: one main type per file, extensions for distinct concerns.
- Swift Testing for `ASBCore` (`@Test func whatItChecks()`, `#expect`, `#require`), XCTest for the app. Test names
  state the behaviour (`aSubagentWaitOutlastsOtherAgentsTheParentsStopAndTaskResults`).
