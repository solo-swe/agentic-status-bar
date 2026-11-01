# The app

The macOS app in `App/`: a menu-bar item, its popover, Settings, Help, notifications and the desktop companion. The
Xcode project is generated from `App/project.yml` (XcodeGen) and isn't committed.

## Which framework for what

- **AppKit** for the system surfaces: the status item (`StatusItemController`), the popover, panels and windows
  (`CompanionWindow`, `EscClosingWindow`), menus, the activation policy.
- **SwiftUI** for content: Settings, Help, the session list rows, first run. Hosted in AppKit windows with
  `NSHostingController`.
- **Core Animation** for anything animated (the companion): layers and keyframe animations the render server runs,
  not redraws driven by timers.

## Structure

- **Stores and view models.** `SessionStore` (`@MainActor @Observable`) holds the snapshot; views read it. Decisions
  a view would otherwise make (a row's text, the status item's presentation, when to notify, which companion scene)
  are computed in a view model or a pure function with its own tests: `RowItem`, `StatusItemController.presentation`,
  `NotificationRules`, `CompanionScene.from(_:)`.
- **No logic in views.** A view lays out what it is given and calls an action. If it needs an `if` about sessions or
  states, that `if` belongs in the core or a view model.
- **Settings write the config file** through `SessionStore.set`, the same file `asb` reads; the app never keeps a
  second copy of a setting.
- **Actions run commands through `CommandRunner`**, which tests replace.

## Behaving as a menu-bar app

- It is an agent app (`LSUIElement`): no Dock icon, except while one of its windows is open (`ActivationPolicy`).
- It never takes the focus unasked. Panels like the companion's are non-activating and click-through except over what
  can be clicked.
- It follows the system: light and dark, accent colors, Reduce Motion, Low Power Mode, multiple displays, Spaces and
  full screen.
- Nothing runs while it can't be seen: animations stop when a window is occluded, the screens sleep or the session
  is locked (`CompanionEnergy`), and work is coalesced (`Coalescer`, at most every 200 ms) rather than done per event.
- Measure energy changes (`top -pid`, Activity Monitor) and record the numbers where the design is written down.

## Testing

- XCTest in `App/Tests/`, hosted by the app; `applicationDidFinishLaunching` does nothing under tests.
- Test view models and pure functions directly. For AppKit, test what can be checked without a screen: window style
  masks and collection behavior, frames from given screen rects, hit areas, the layer tree a pose produces.
- What only a person can see (placement on real displays, Spaces, full screen, Stage Manager, animation feel) is a
  live check with the user in the dev build: `tests/app.sh --run`, with `ASB_STATE_DIR` and `ASB_CONFIG` pointing at
  scratch fixtures when a specific state is needed.
