# Agentic Status Bar

Shows, in one menu-bar item, whether any running [Claude Code](https://claude.com/claude-code) agent needs you. Today it runs as a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin on top of `asb`, a Swift command-line tool; a standalone macOS app is in progress (see [the design](doc/design/future-architecture.md)).

> **Status: pre-release.** See the [PRD](doc/PRD.md) for the full design.

<!-- Screenshots: doc/screenshots/waiting.png, idle.png, uncertain.png, busy.png, dropdown.png -->

## What it shows

The menu-bar item shows one icon for the most urgent state across all sessions, with the number of sessions in that state. States are checked top to bottom, and the first that applies wins:

| Icon                              | Color      | Number          | Meaning                                                                   |
| --------------------------------- | ---------- | --------------- | ------------------------------------------------------------------------- |
| Warning triangle                  | Orange (yellow in dark mode) | All sessions | Some state files couldn't be read (see Troubleshooting)                   |
| Filled exclamation circle         | Red        | Waiting         | An agent is waiting on a permission prompt or a question                  |
| `zzz`                             | Orange (yellow in dark mode) | Idle | An agent has finished and is waiting for your next prompt                 |
| Question mark in a circle         | Gray       | Stale           | A busy agent has shown no activity for longer than the stale threshold    |
| Sparkle (the `icon` setting)      | Dim gray   | All sessions    | All agents are working, or waiting on their own subagents; nothing needs you |
| Bell with a slash, no number      | Gray       | —               | Every session is in a muted project                                       |
| Sparkle, no number                | Very faint | —               | No Claude Code sessions running                                           |

Because only the most urgent state is shown, a red `1` can hide idle sessions behind it; the dropdown lists every session with its own state. The icons never animate. Each icon and its number share the state's color, in the menu bar and on the session's row in the dropdown.

The dropdown lists every session, most urgent first, then the filters and settings. Each row starts with the same icon and color as the menu bar uses for its state (drawn here as `!`, `z`, `?`, `✦` and `⌛`):

```
! api-gateway — Add rate limiting to auth routes   permission · 2m
z web-dashboard — Fix flaky login test             idle · 14m
? data-pipeline — Refactor CSV parser              no activity · 41m
✦ docs-site — Migrate to the new theme             working · 30s
⌛ search-index — Rebuild the ranking              waiting on 2 subagents · 3m
  ↳ subagent: Explore                              working · 3m
  ↳ subagent: Plan                                 working · 1m
---
Show
  ✓ Interactive
  ✓ Headless (claude -p)
  ✓ Subagents
  ✓ IDE / Desktop
Settings…
---
Refresh
```

A session whose subagents are still running, after its own turn ended or while it waits in its Task tool, shows an hourglass and `waiting on N subagents`. In the menu bar it counts as working, not idle.

Row titles come from the herdr terminal title, a session name you gave the session, or the first prompt, in that order.

If a session runs in a [herdr](https://herdr.dev) pane, clicking its row jumps to that pane. Without herdr, clicking does nothing, and each row's submenu still lets you copy the session ID or working directory, open the folder or reveal the transcript. Support for other tools (VS Code, other terminals) is planned.

### Muting a project

Not working on a project today? Its idle `zzz` doesn't have to sit in the menu bar. Each row's submenu has **Mute project for 1 hour** and **Mute project for today** (until midnight). A mute covers every session in that project folder, including ones you start later:

- muted sessions don't count in the menu bar and move to the bottom of the dropdown with a gray bell-with-slash icon and `muted until 18:40` or `muted today`;
- a muted session that is waiting on a permission prompt or a question still turns the menu bar red;
- sending a prompt in a muted project unmutes it;
- **Unmute project** in the submenu, or **Unmute all projects** above the filters, ends a mute early.

## How it works

1. **Claude Code hooks** (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SessionEnd`, subagent events) run `asb hook`, which writes one small JSON state file per session to `~/.claude/agentic-status-bar/` ([the format](doc/state-file-schema.md)).
2. **The SwiftBar plugin** runs `asb swiftbar` every 5 seconds, or right away when a hook asks SwiftBar to refresh. It reads those files and corrects states the hooks can't see:
   - removes sessions whose process has exited,
   - shows sessions as idle after Esc or a denied permission,
   - shows sessions running an approved long tool as busy, not waiting,
   - uses Claude Code's own session registry when it is present and newer,
   - marks anything else that has gone quiet for too long as `?` rather than guessing.

Everything stays on your machine. Hooks run async and always exit 0, so they can't slow down or break Claude Code; `asb hook` takes about 9 ms.

## Requirements

- macOS 14 or later
- Xcode 16 or later (to build `asb`)
- [SwiftBar](https://github.com/swiftbar/SwiftBar) 2.x
- Claude Code with hooks support
- Optional: [herdr](https://herdr.dev) for jumping to the exact pane

## Install

Clone the repo and build `asb`:

```sh
git clone https://github.com/hakanserce/swiftbar-claudecode-minimal.git ~/code/agentic-status-bar
cd ~/code/agentic-status-bar
swift build -c release
.build/release/asb install
```

`asb install`:

- copies `asb` to `~/Library/Application Support/agentic-status-bar/bin/asb`, so moving or deleting the repo later doesn't break the hooks;
- adds the hooks to `~/.claude/settings.json`, after backing it up, leaving your other settings and hooks exactly as they are;
- links the plugin into SwiftBar's plugin folder;
- moves state and config from the older SwiftBar plugin (Minimalist Claude Code Statusbar) and replaces its hooks.

Running it again changes nothing. Hooks load when a session starts, so restart running Claude Code sessions, or wait for their next event (sessions that were already running fill in their details then).

To remove everything it added, run `asb uninstall`. It asks before deleting state files and config (`--purge` deletes them without asking).

There is no Claude Code plugin package any more: the hooks run the installed `asb`, so `asb install` is the one way in.

## Configuration

Settings live in `~/.config/agentic-status-bar/config` (`key=value`). The dropdown's **Show** and **Settings** items change them for you, and **Settings… → Reveal config file** opens it.

| Key                                                               | Default                                 | Meaning                                                                  |
| ----------------------------------------------------------------- | --------------------------------------- | ------------------------------------------------------------------------ |
| `show_interactive`, `show_headless`, `show_subagents`, `show_ide` | `1`                                     | Which session types to show (`show_ide` covers IDE and desktop sessions) |
| `stale_minutes`                                                   | `30`                                    | Minutes without activity before a busy session shows `?`; `0` = off      |
| `use_registry`                                                    | `1`                                     | Use Claude Code's session registry when it is newer                      |
| `instant_refresh`                                                 | `1`                                     | Hooks trigger an immediate SwiftBar refresh                              |
| `theme`                                                           | `default`                               | `default`, `monochrome` or `high_contrast`; also under **Settings… → Theme** |
| `icon_<state>`, `color_<state>`                                   | from the theme                          | Override one state's SF Symbol name, and its `#RRGGBB` color or `light,dark` pair. States: `waiting`, `idle`, `uncertain`, `busy`, `subagents`, `muted`, `none`, `warning` |
| `icon`                                                            | from the theme                          | Older shortcut: SF Symbol for both the busy and empty icon               |
| `store_prompt_preview`                                            | `1`                                     | Keep an 80-character prompt preview for row titles                       |
| `state_dir`                                                       | `~/.claude/agentic-status-bar`          | Where hooks write state files                                            |

For example, to show idle sessions as a blue moon:

```
icon_idle=moon.zzz
color_idle=#0040DD,#64D2FF
```

**Settings… → Start SwiftBar at login** adds a login item (`~/Library/LaunchAgents/agentic-status-bar.start-swiftbar.plist`) that opens SwiftBar in the background when you log in; clicking it again removes it. It takes effect at your next login and doesn't touch SwiftBar's own "Launch at login" preference, so you don't need both. macOS may show a "Background item added" notice the first time.

## Troubleshooting

- **"Agentic Status Bar needs asb" in the menu:** build it with `swift build -c release` and run `.build/release/asb install`.
- **A session doesn't appear:** it was started before the hooks were installed and hasn't had an event since. Send it a prompt, or restart it.
- **Warning triangle:** a state file in `~/.claude/agentic-status-bar/` is corrupt or from a newer version. Delete the file or update; a running session writes a fresh one on its next event.
- **`asb install` skipped the SwiftBar link:** SwiftBar has no plugin folder yet. Open SwiftBar once to choose one, then run `asb install` again.
- **Something looks wrong:** messages are logged to `~/.claude/agentic-status-bar/plugin.log`, for example when Claude Code's session registry changes format. `asb snapshot --json --pretty` shows exactly what the menu is built from.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md): `tests/swift.sh`, `tests/run.sh`, `tests/lint.sh` and `tests/run.sh --bench`.

## Roadmap

1. **Done:** hooks, state files, menu bar and dropdown, accuracy checks, herdr focus, filters, mutes, themes
2. **Done:** the move from shell and jq to Swift (`asb`)
3. **In progress:** a standalone macOS app with notifications, replacing SwiftBar
4. **Later:** atm integration, Homebrew, focus support for VS Code and other terminals

## License

[MIT](LICENSE)
