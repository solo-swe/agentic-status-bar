# Documents

| Document | What it covers |
| --- | --- |
| [PRD.md](PRD.md) | What the app does and why: goals, UX, architecture, the state model, the reconciliation checks C1–C5, non-functional requirements, risks |
| [state-file-schema.md](state-file-schema.md) | The per-session state file the hook writes: fields, how each hook event changes it, writer and reader rules, the config file |
| [snapshot-schema.md](snapshot-schema.md) | The snapshot the engine computes for the menu bar, the list and `asb snapshot --json` |
| [RELEASING.md](RELEASING.md) | How a release is built, signed, notarized, published and delivered; one-time setup; checking a release; failures |
| [design/future-architecture.md](design/future-architecture.md) | The move from a SwiftBar plugin to a Swift core and a native app |
| [design/desktop-companion.md](design/desktop-companion.md) | The animated desktop companion: window, rendering, animations, energy, decisions |
| [design/agent-providers.md](design/agent-providers.md) | Proposal: showing coding agents other than Claude Code |
| [design/focus-targets.md](design/focus-targets.md) | Proposal: jumping to a session in other terminals and apps |
| [design/dev-tooling.md](design/dev-tooling.md) | mise for pinned tools and tasks: the decision, the options considered, the layout |

## Guides

How code is written here, by area:

| Guide | For |
| --- | --- |
| [guides/swift.md](guides/swift.md) | Swift in `ASBCore`, `asb` and the app |
| [guides/app.md](guides/app.md) | The macOS app: AppKit, SwiftUI, Core Animation |
| [guides/hook.md](guides/hook.md) | `asb hook` and the state files |
| [guides/shell.md](guides/shell.md) | The scripts in `tests/` and `scripts/` |

## Elsewhere

- [README.md](../README.md): what users see, install, settings and the config keys.
- [CONTRIBUTING.md](../CONTRIBUTING.md): requirements, checks, layout, running the app and `asb`.
- [tests/conformance/README.md](../tests/conformance/README.md): the conformance suite's case format.
- [tests/fixtures/README.md](../tests/fixtures/README.md): captured Claude Code payloads and what they showed.
