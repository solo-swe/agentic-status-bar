# Desktop companion: an animated character outside the menu bar

Status (2026-11-01): **built** (T-127 to T-140), released in v0.3.0. The idea: a small stick person on the desktop that
acts out what the sessions are doing. It walks while they work, waves at you when one needs you, and sleeps in a
tiny bed with *zzz* rising when they're all idle. Research sources are listed at the end; what was unverified
when this was written was checked with the user in the dev build (T-140).

## Short answer: what it takes

- **No new data.** The app already has everything the character needs: `SessionStore` publishes a snapshot with
  the most urgent state, and the status item already observes it. The hook, the state file and `ASBCore` don't
  change.
- **One new window.** A borderless, transparent, non-activating `NSPanel` that floats above other windows on every
  Space. It needs no permissions: drawing your own window doesn't need Accessibility or Screen Recording.
- **A character drawn in code.** Eleven Core Animation layers make a stick-figure skeleton. The poses are sets
  of joint angles, and keyframe animations move between them. The system's render server plays the animations, so
  between state changes the app runs no code per frame. There are no dependencies and no art files.
- **Etiquette.** Off by default. Small, near the Dock, click-through. It stops animating when it can't be seen, on
  Low Power Mode, or with the screen locked, and it holds still poses under Reduce Motion.
- **Size of the job.** Fourteen small tasks (below). The first visible milestone, a figure that works out, waves
  and sleeps on the desktop, took the first nine.

## What it builds on

The pieces of the app the companion uses:

| Piece | Where | What it gives |
| --- | --- | --- |
| Snapshot | `App/Sources/SessionStore.swift` (`@Observable`, `snapshot`) | Recomputed within 200 ms of any state file change, and every 5 s |
| Header state | `Snapshot.Header.state` (`Sources/ASBCore/Snapshot.swift`) | `warning`, `waiting`, `idle`, `uncertain`, `busy`, `muted`, `none`: the most urgent first |
| Sessions | `Snapshot.sessions[]` | Per session: `shown` (`waiting`, `idle`, `uncertain`, `busy`, `subagents`), `reason` (`permission`, `question`), `since`, `muted`, `subagents[]`, `focusable` |
| Observing | `StatusItemController.observe()` | `withObservationTracking` on `store.snapshot`; the companion does the same |
| Theme colors | `Sources/ASBCore/Themes.swift` | A light,dark color per state, which tints the speech bubble |
| Actions | `SessionStore.perform` (`focus`, mutes) and `StatusItemController.showPopover()` | What a click on the character can do |
| Settings | `Config` keys in the config file the CLI shares (`Sources/ASBCore/Config.swift`) | The `companion*` keys (Settings, below) |

The app targets macOS 14 and has a single dependency (Sparkle); the release DMG is about 3.5 MB. That favors
drawing the character in code over adding an animation runtime.

## The window

A floating panel (`App/Sources/CompanionWindow.swift`), configured like this (from an Apple DTS engineer's answer on
the developer forums, tested on macOS 26 over full-screen apps [1]):

```swift
let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.level = .floating                     // .screenSaver only with "Show over full-screen apps"
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false                     // a shadow would trace the drawn shape
panel.ignoresMouseEvents = true             // click-through; see Interaction
panel.orderFrontRegardless()
```

- **Non-activating.** Showing a normal window activates its app, which can pull you out of a full-screen app's
  Space. A `.nonactivatingPanel` never takes focus. The app already runs as an accessory (no Dock icon), which
  the recipe assumes [1].
- **Level.** `.floating` stays above normal windows but below full-screen apps. That's polite, and it's the
  default. A setting can raise it to `.screenSaver` to stay visible over full-screen apps, as the DTS engineer
  did [1].
- **Spaces.** With `.canJoinAllSpaces` the panel shows on every Space without listening for Space changes [1];
  `.stationary` keeps it in place in Mission Control [2]; `.ignoresCycle` keeps it out of ⌘\`.
- **Where it lives.** A strip 260 × 60 drawing units (the figure is about 42 tall) in a corner of the main screen's
  `visibleFrame`, 16 pt from the side, chosen in Settings: bottom-right (default, just above a bottom Dock),
  bottom-left, top-right or top-left (just under the menu bar). `companion_size` scales the strip and everything
  in it: 1× (small), 1.5× (medium, the default) or 2× (large). It follows screen changes
  (`NSApplication.didChangeScreenParametersNotification`) and the Dock moving or hiding. Checked with the user
  (T-140) in every corner with the Dock at the bottom, on the left and hidden, over full-screen apps, across Spaces
  and Mission Control, with Stage Manager, and with two displays.

## Rendering: options compared

| Option | Effort | Energy | Size, license | Fit |
| --- | --- | --- | --- | --- |
| **Core Animation layer skeleton** (`CAShapeLayer` limbs, `CAKeyframeAnimation` on rotations) | Medium | Lowest: the render server plays the animations; no app code runs per frame [3] | None | **Recommended.** A joint-angle rig is exactly a layer tree with anchor points at the joints |
| SwiftUI `Canvas` + `TimelineView` | Low | The app redraws every frame on the CPU; there are reports of 15–30 % CPU from timeline-driven animation on macOS [4] | None | Fine for a prototype; it must pause whenever nothing moves |
| SpriteKit (`SKView`, `allowsTransparency`) [5] | Medium | A game loop; pausable | System | Overkill for a stick figure; suits sprite-sheet art |
| Rive (`RiveRuntime`) [6][7] | Little code, but the art is authored in the Rive editor | GPU renderer; `fps` and pause controls | MIT runtime; about 1.9 MB download and 4.8 MB installed | The best third-party option: its state machines map onto our states. Worth it only with a designer |
| Lottie (`lottie-spm`) [8] | Little code; art in After Effects | Core Animation engine | Apache-2.0; about 8 MB | Playback only, with no state machines; dotLottie adds them but renders on the CPU by default [9] |

Recommendation: the **Core Animation skeleton**, drawn procedurally in code: a stick figure is a few lines and a
circle. If the look ever outgrows code (a real character, a designer), the scene controller stays and only the
renderer changes to Rive.

## The character

### Rig

Built in `App/Sources/Companion/`: `Pose.swift` (the pose and the skeleton's math), `StickFigure.swift` (the
layers and their animations) and `Moves.swift` (the moves as pose lists).

- **Bones.** Eleven zero-size layers, each at its joint and drawing its own line: the hips (the root), the torso, the
  head, and a back and a front upper arm, forearm, thigh and shin. The bones a bone carries sit at its tip, so
  turning a bone turns everything below it.
- **Side view.** The figure is seen from the side, facing right; facing left mirrors the whole layer. Limbs are
  *back* and *front* rather than left and right, and the back ones are drawn under the front ones, a little lighter,
  so a side view reads which leg is which.
- **A pose** is joint angles in radians plus where the hips are. Limbs at 0 hang straight down; a positive shoulder
  or hip angle swings the limb forward, a positive elbow or knee bends the lower part forward. `body` tips the
  whole figure around the hips (lying down for push-ups and in bed); `lean` tilts the torso, `neck` the head.

  ```swift
  struct Pose { var hipY, hipX, body, lean, neck: CGFloat
                var shoulderBack, elbowBack, shoulderFront, elbowFront, hipBack, kneeBack, hipFront, kneeFront: CGFloat }
  ```
- **The skeleton** (`Skeleton`) holds the bone lengths and computes where the joints are for a pose, by the same
  forward kinematics the layers do. For hands that have to hold something (the barbell, the pull-up bar), it also
  solves the arm's two bones for a target point (two-bone inverse kinematics), with the elbow bent behind, in front,
  or out to the side.
- **Animations.** A move is a list of poses; it plays as one `CAKeyframeAnimation` per joint
  (`transform.rotation.z`) with the same key times for all, eased between poses and cut into discrete still frames at
  the energy's frame rate (12 a second, 6 in Low Power Mode). Slow moves such as breathing play smoothly instead,
  where steps would show. The render server plays them.

Strokes use the label color (dark on a light desktop, light on a dark one), or `companion_color`; a halo in the
opposite brightness keeps the figure visible on any wallpaper. Only the speech bubble takes the state's theme
color.

### Animations

- **Walk.** The classic eight poses: contact, down, passing and up, then the same mirrored [10][11]. The hips are
  lowest at *down* and highest at *up*. A cycle lasts 1 s. Horizontal travel matches two strides per cycle, so the
  feet don't slide. The figure turns to face the way it walks.
- **Workouts.** Each is an activity: an intro from standing, reps of a loop, and an outro back to standing.
  - Weight lifting: squat, clean the barbell to the shoulders, then push presses (dip, press overhead, hold,
    lower).
  - Push-ups: down into a plank; the hands and feet stay planted while the body lowers and rises.
  - Jumping jacks, seen from the front: hop, land with the legs apart and the arms up, hop back together.
  - Pull-ups, seen from the front: reach up and hang, pull until the chin is over the bar, lower.

  Props (the barbell, the pull-up bar) are a few lines each, drawn only while in use.
- **Busy routine (calm).** One activity for about 8–15 s, then a rest of about 4–8 s (standing, a slow breath),
  then a different activity chosen at random: a stroll or a workout on the stretch of the strip off the bed. Never
  two of the same in a row. Under Low Power Mode the rests are twice as long.
- **Wave.** Stop, face you, raise the front arm, swing the forearm 3 times (about 1.5 s), lower it, wait about 2 s,
  repeat. A small bubble shows **!** for a permission and **?** for a question, in the waiting color.
- **Sleep.** Walk to the bed, sit on its edge, lie down on its back with the head on the pillow, and breathe (the
  chest and head rise a little, 4 s per breath). Three *z* glyphs rise, drift and fade in a slow loop.
- **The bed** stands at the strip's end toward the middle of the screen, its headboard at the outer end.
- **Transitions.** Every change blends through a standing pose in 0.3 s, so the figure never snaps.

### State → animation

| Header state | The character |
| --- | --- |
| `busy` | Works out, calmly: one activity for a while (walking, weight lifting, push-ups, jumping jacks, pull-ups on a small bar), then a rest, then another |
| `busy` with subagents running | The same, with one tiny follower per running subagent (up to 3), copying its moves a moment later |
| `waiting` (permission) | Waves, with **!** |
| `waiting` (question) | Waves, with **?** |
| `idle` | Sleeps in its bed, *zzz* |
| `uncertain` | Stands and scratches its head, with **•••** in the menu bar's color |
| `muted` (only muted sessions) | Sits on its bed and reads a book |
| `warning` (hooks missing) | Holds up a small sign with a wrench, swaying a little; a click opens Settings |
| `none` (no sessions) | Sits on the edge of its bed, tilting its head now and then |

Under Reduce Motion each scene is one still pose of the same, with its prop or bubble.

**Several sessions.** One character acts out the menu bar's header state, so the two always agree: waiting,
then idle, then uncertain, then busy. Two idle sessions and a busy one sleep, as the menu bar shows *zzz*. One
character per session would
be fun but crowded and costly. That could come later, as small followers.

## Energy and etiquette

Rules (APIs from Apple's docs [12]–[15]):

- **Stop when unseen.** Stop everything (animations, props and the routine's timers) when the panel's occlusion
  state isn't `.visible` [12], when the displays sleep (`NSWorkspace.screensDidSleepNotification`) [14], and when
  the screen locks (the `com.apple.screenIsLocked` distributed notification, undocumented but widely used); play the
  current scene again from the start when it can be seen. (Freezing with `layer.speed = 0` would leave the timers
  running.) Built: `CompanionEnergy`, `CompanionEnergyWatcher`.
- **Low Power Mode.** On `NSProcessInfoPowerStateDidChange`, read `ProcessInfo.isLowPowerModeEnabled` [13]. Moves at
  6 still frames a second instead of 12, and twice as long rests between activities.
- **Reduce Motion.** With `NSWorkspace.accessibilityDisplayShouldReduceMotion` set [15], show one still pose per
  state, swapped on change.
- **No App Nap opt-out.** Don't call `beginActivity`; napping is fine for a decoration.
- **Frame rate.** A stick figure reads well at 12 fps ("on twos"). Keyframes with `calculationMode = .discrete` at
  12 steps per second keep the render server's work low and give a hand-drawn feel. Asleep, only a slow breath and
  the *zzz* loop move, both smooth.
- **Budget.** Averaged over a minute: under 1 % CPU walking and about 0 % asleep or hidden, measured with
  `top -pid` and Activity Monitor's Energy tab on an Apple-silicon Mac. Measured below.

### Measured (2026-10-31)

The app's CPU over 60 s (`top -l 2 -s 60 -pid <pid>`, CPU time used in the minute), debug build, MacBook Air
(Apple silicon), macOS 26.5, medium size (1.5×), with the halo. Each scene ran against a one-session fixture
(`ASB_CONFIG`, `ASB_STATE_DIR` passed to the dev build, today `mise run app:run KEY=VALUE`), so nothing else
changed the snapshot.

| Scene | CPU time in 60 s | Average |
| --- | --- | --- |
| Companion off (baseline) | 0.19 s | 0.3 % |
| Busy (the workout routine) | 0.20 s | 0.3 % |
| Waiting (the wave loop) | 0.19 s | 0.3 % |
| Idle, live sessions (walk to bed, then asleep) | 0.54 s | 0.9 %; 0.4 % once asleep |

The companion adds no measurable CPU to the app: the render server plays the keyframes, and the controller only
runs code when a scene or activity changes. The baseline is the app's own refresh (every 5 s). The render server's
work (WindowServer) isn't in these numbers; that includes the halo's shadow pass. WindowServer's energy impact
was compared in Activity Monitor with the companion on and off, with and without the halo, in the check with the
user (T-140, 2026-11-01), and found fine; no numbers were recorded.

Etiquette: **off by default** (Settings and the first-run window offer it). It's click-through except on the figure
itself, never covers more than its strip, can be hidden from its right-click menu, and never steals focus or the
cursor. The prior art shows what goes wrong otherwise: Desktop Goose's users called it annoying, and it needs
a hold-Esc kill switch [16][17].

## Interaction

The whole panel is click-through (`ignoresMouseEvents = true`), since "transparent pixels don't take clicks" is
undocumented and regressed in Sonoma [18]. Mouse-moved monitors (global, and local while the panel takes the mouse;
neither needs Accessibility) turn clicks on only while the cursor is over the figure. The hit area is a box around
the figure in drawing units, scaled with `companion_size`, and wider while it lies down (in bed, push-ups).

- **Click:** the waiting session's terminal is focused when it is focusable; on a warning Settings opens; otherwise
  the session list opens (`showPopover`).
- **Drag:** moves the strip; on release it snaps to the nearest corner and saves it as `companion_position`.
- **Right-click:** Show Sessions, Hide Companion (turns `companion` off), Settings….

## Settings

Config keys, shared with the CLI like the others (also in `state-file-schema.md` › Config file):

| Key | Default | Meaning |
| --- | --- | --- |
| `companion` | `0` | Show the character |
| `companion_position` | `bottom-right` | `bottom-right`, `bottom-left`, `top-right` or `top-left` |
| `companion_size` | `medium` | `small` (1×), `medium` (1.5×) or `large` (2×) |
| `companion_color` | empty | The strokes' color: `#RRGGBB` or a light,dark pair; empty is the label color (dark or light) |
| `companion_over_fullscreen` | `0` | Stay visible over full-screen apps (`.screenSaver` level) |

Settings shows them in a Companion tab: the on/off switch, a corner picker, a size picker, a color palette with
Automatic, and the full-screen switch; the others are disabled while the companion is off.

## Prior art

- **RunCat**: a cat in the menu bar that runs faster with CPU load. It's the precedent for "the animation shows the
  load", but it lives in the bar [19][20].
- **Neko ports** (OnekoMac: Swift, Metal, chases the cursor) [21]; **Shimeji** (Shijima-Qt: Qt, needs
  Accessibility to climb windows, archived) [22]; **BongoCat** (Tauri) [23]; **Desktop Goose** (a prank that
  steals the cursor) [16].
- **Claude Code pets** (2025–26): community projects such as hxri/claude-pet (Swift: types while Claude works,
  **!** when input is needed) [24], peon-pet (Electron + Three.js) [25] and claude-pet in Tauri [26]. Most install
  their own hooks. A native, low-energy companion that reuses our state and checks (C1–C5) would be more accurate
  and lighter than those.

## Decisions (2026-10-31)

1. **Placement is a setting**, along with on/off: a corner, bottom or top, left or right (`companion_position`).
2. **Busy is calm**: not walking all the time, but a routine of activities (walking, weight lifting, push-ups,
   jumping jacks, pull-ups) with rests between them.
3. **One character** for the most urgent state, for now.
4. **No sessions**: it sits on the edge of its bed.

## Risks

- **Distraction.** It's off by default, rests between activities, uses still poses under Reduce Motion, and hides
  from its right-click menu.
- **Full-screen apps and Stage Manager.** Checked with the user (T-140): hidden behind full-screen apps unless
  `companion_over_fullscreen` is on, and fine with Stage Manager.
- **Multiple displays.** It stays on the main screen; the menu bar's screen may be a better choice.
- **Energy.** Measured within the budget (Measured, above).
- **Scope creep.** Per-session characters, custom skins and Rive art are all later.

## Task breakdown

The sprints Desktop companion and Animated Companion, label `companion`; T-127 to T-140, all done. Each task was
under 10 minutes; app tests run with `mise run app:test`.

1. **Config keys** `companion`, `companion_position`, `companion_over_fullscreen` (`companion_size` and
   `companion_color` came with the Settings and panel reviews).
2. **Companion panel** (1): the `NSPanel`, its strip in the chosen corner, screen and Dock changes.
3. **Rig and poses** (2): `StickFigure`, `Pose`, applying a pose.
4. **Walk** (3).
5. **Weight lifting and push-ups** (3).
6. **Jumping jacks and pull-ups** (3).
7. **Wave and bubble** (3).
8. **Sleep and the bed** (3), including sitting on the bed's edge.
9. **Scene controller** (4–8): header → scene, the calm busy routine, transitions. **First milestone: check it live
   with the user.**
10. **The other states** (9): subagent followers, uncertain, muted, warning.
11. **Energy** (9): pausing, Low Power Mode, Reduce Motion; measure against the budget.
12. **Interaction** (9): the figure-only hit area, click, drag to a corner, right-click menu.
13. **Settings and Help** (1, 9): the Companion section, Help, README, first-run offer.
14. **Full-screen, Stage Manager and multi-display check** (11, 12, 13): a manual pass with the user.

## Sources

Fetched 2026-10-31.

1. Apple Developer Forums, DTS answer on floating panels over full-screen apps (May 2026): https://origin-devforums.apple.com/forums/thread/826308
2. WebKit bug 242082, `.stationary` for Stage Manager: https://auto-bugs.webkit.org/show_bug.cgi?id=242082
3. `NSView.displayLink(target:selector:)` (macOS 14): https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:)
4. Apple Developer Forums, SwiftUI animation CPU on macOS: https://developer.apple.com/forums/thread/768768
5. `SKView.allowsTransparency`: https://developer.apple.com/documentation/spritekit/skview/allowstransparency
6. Rive Apple runtime: https://rive.app/docs/runtimes/apple, https://github.com/rive-app/rive-ios
7. Rive runtime sizes, rive-ios 6.27.0: https://rive.app/docs/runtimes/runtime-sizes, https://github.com/rive-app/rive-ios/releases/tag/6.27.0
8. lottie-spm: https://github.com/airbnb/lottie-spm
9. dotlottie-ios: https://github.com/LottieFiles/dotlottie-ios
10. Walk cycle assignment (UW CSE 459): https://courses.cs.washington.edu/courses/cse459/19au/assignments/assignment_5/
11. Walk cycle basics: https://garagefarm.net/blog/walk-cycle-easy-steps-to-animate-walking-animation-for-beginners (after Richard Williams, *The Animator's Survival Kit*)
12. `NSWindow.didChangeOcclusionStateNotification`: https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification
13. `ProcessInfo.isLowPowerModeEnabled`, `NSProcessInfoPowerStateDidChange` (macOS 12): https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled
14. `NSWorkspace.screensDidSleepNotification`: https://developer.apple.com/documentation/appkit/nsworkspace/screensdidsleepnotification
15. `NSWorkspace.accessibilityDisplayShouldReduceMotion`: https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion
16. Desktop Goose: https://samperson.itch.io/desktop-goose
17. Desktop Goose reviews: https://www.snapfiles.com/get/desktopgoose.html, https://gigazine.net/news/20200131-desktop-goose
18. Apple Developer Forums, click-through on transparent pixels in Sonoma: https://developer.apple.com/forums/thread/737584
19. RunCat: https://forest.watch.impress.co.jp/docs/news/2037727.html
20. RunCatNeo: https://github.com/runcat-dev/RunCatNeo
21. OnekoMac: https://github.com/hellov3an/OnekoMac
22. Shijima-Qt: https://github.com/pixelomer/Shijima-Qt
23. BongoCat: https://github.com/ayangweb/BongoCat
24. hxri/claude-pet: https://github.com/hxri/claude-pet
25. peon-pet: https://github.com/PeonPing/peon-pet
26. IMMINJU/claude-pet: https://github.com/IMMINJU/claude-pet
