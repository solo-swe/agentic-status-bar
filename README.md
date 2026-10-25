# Minimalist Claude Code Statusbar

A minimal [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that shows, in one menu-bar item, whether any running [Claude Code](https://claude.com/claude-code) agent needs you.

> **Status: release candidate (1.0.0-rc.1).** See the [PRD](doc/PRD.md) for the full design.

<!-- Screenshots: doc/screenshots/waiting.png, idle.png, uncertain.png, busy.png, dropdown.png -->

## What it shows

The menu-bar item shows one icon for the most urgent state across all sessions, with the number of sessions in that state. States are checked top to bottom, and the first that applies wins:

| Icon                              | Color      | Number          | Meaning                                                                   |
| --------------------------------- | ---------- | --------------- | ------------------------------------------------------------------------- |
| Warning triangle                  | Yellow     | All sessions    | Some state files couldn't be read (see Troubleshooting)                   |
| Filled exclamation circle         | Red        | Waiting         | An agent is waiting on a permission prompt or a question                  |
| `zzz`                             | Orange     | Idle            | An agent has finished and is waiting for your next prompt                 |
| Question mark in a circle         | Gray       | Stale           | A busy agent has shown no activity for longer than the stale threshold    |
| Sparkle (the `icon` setting)      | Dim gray   | All sessions    | All agents are working; nothing needs you                                 |
| Bell with a slash, no number      | Gray       | —               | Every session is in a muted project                                       |
| Sparkle, no number                | Very faint | —               | No Claude Code sessions running                                           |

Because only the most urgent state is shown, a red `1` can hide idle sessions behind it; the dropdown lists every session with its own state. The icons never animate.

The dropdown lists every session, most urgent first, then the filters and settings. Each row starts with the same icon and color as the menu bar uses for its state (drawn here as `!`, `z`, `?` and `✦`):

```
! api-gateway — Add rate limiting to auth routes   permission · 2m
z web-dashboard — Fix flaky login test             idle · 14m
? data-pipeline — Refactor CSV parser              no activity · 41m
✦ docs-site — Migrate to the new theme             working · 30s
  ↳ subagent: Explore                              working · 12s
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

Row titles come from the herdr terminal title, a session name you gave the session, or the first prompt, in that order.

If a session runs in a [herdr](https://herdr.dev) pane, clicking its row jumps to that pane. Without herdr, clicking does nothing, and each row's submenu still lets you copy the session ID or working directory, open the folder or reveal the transcript. Support for other tools (VS Code, other terminals) is planned.

### Muting a project

Not working on a project today? Its idle `zzz` doesn't have to sit in the menu bar. Each row's submenu has **Mute project for 1 hour** and **Mute project for today** (until midnight). A mute covers every session in that project folder, including ones you start later:

- muted sessions don't count in the menu bar and move to the bottom of the dropdown with a gray bell-with-slash icon and `muted until 18:40` or `muted today`;
- a muted session that is waiting on a permission prompt or a question still turns the menu bar red;
- sending a prompt in a muted project unmutes it;
- **Unmute project** in the submenu, or **Unmute all projects** above the filters, ends a mute early.

## How it works

1. **Claude Code hooks** (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SessionEnd`, subagent events) write one small JSON state file per session to `~/.claude/swiftbar-claudecode-minimal/`.
2. **The SwiftBar plugin** reads those files every 5 seconds, or right away when a hook asks SwiftBar to refresh, and corrects states the hooks can't see:
   - removes sessions whose process has exited,
   - shows sessions as idle after Esc or a denied permission,
   - shows sessions running an approved long tool as busy, not waiting,
   - uses Claude Code's own session registry when it is present and newer,
   - marks anything else that has gone quiet for too long as `?` rather than guessing.

Everything stays on your machine. Hooks run async and always exit 0, so they can't slow down or break Claude Code.

## Requirements

- macOS 15 or later (ships `/usr/bin/jq`; on older macOS, `brew install jq`)
- [SwiftBar](https://github.com/swiftbar/SwiftBar) 2.x
- Claude Code with hooks support
- Optional: [herdr](https://herdr.dev) for jumping to the exact pane

## Install

Clone the repo somewhere permanent; SwiftBar runs the plugin from it:

```sh
git clone https://github.com/hakanserce/swiftbar-claudecode-minimal.git ~/code/swiftbar-claudecode-minimal
cd ~/code/swiftbar-claudecode-minimal
```

Then pick one way to register the hooks.

**Option A: install script.** Adds the hooks to `~/.claude/settings.json` (after backing it up) and links the plugin into SwiftBar's plugin folder:

```sh
./install.sh
```

Your existing hooks are left exactly as they are. Running it again adds nothing. To remove it, run `./uninstall.sh`; it removes only what `install.sh` added and asks before deleting state files and config (`--purge` skips the question).

**Option B: Claude Code plugin.** Registers the hooks without editing `settings.json`. Inside Claude Code:

```
/plugin marketplace add ~/code/swiftbar-claudecode-minimal
/plugin install swiftbar-claudecode-minimal@swiftbar-claudecode-minimal
```

Then link the SwiftBar plugin yourself:

```sh
ln -s "$PWD/swiftbar/swiftbar-claudecode-minimal.5s.sh" "$(defaults read com.ameba.SwiftBar PluginDirectory)/"
```

Hooks load when a session starts, so restart running Claude Code sessions to see them in the menu bar.

## Configuration

Settings live in `~/.config/swiftbar-claudecode-minimal/config` (`key=value`). The dropdown's **Show** and **Settings** items change them for you, and **Settings… → Reveal config file** opens it.

| Key                                                               | Default                                 | Meaning                                                                  |
| ----------------------------------------------------------------- | --------------------------------------- | ------------------------------------------------------------------------ |
| `show_interactive`, `show_headless`, `show_subagents`, `show_ide` | `1`                                     | Which session types to show (`show_ide` covers IDE and desktop sessions) |
| `stale_minutes`                                                   | `30`                                    | Minutes without activity before a busy session shows `?`; `0` = off      |
| `use_registry`                                                    | `1`                                     | Use Claude Code's session registry when it is newer                      |
| `instant_refresh`                                                 | `1`                                     | Hooks trigger an immediate SwiftBar refresh                              |
| `icon`                                                            | `sparkle`                               | SF Symbol name for the busy and empty menu-bar icon                      |
| `store_prompt_preview`                                            | `1`                                     | Keep an 80-character prompt preview for row titles                       |
| `state_dir`                                                       | `~/.claude/swiftbar-claudecode-minimal` | Where hooks write state files                                            |

## Troubleshooting

- **"Minimalist Claude Code Statusbar needs jq" in the menu:** install it with `brew install jq` (macOS 14 or older).
- **A session doesn't appear:** it was started before the hooks were installed. Restart it.
- **Warning triangle:** a state file in `~/.claude/swiftbar-claudecode-minimal/` is corrupt or from a newer version of Minimalist Claude Code Statusbar. Delete the file or update; a running session writes a fresh one on its next event.
- **`install.sh` skipped the SwiftBar link:** SwiftBar has no plugin folder yet. Open SwiftBar once to choose one, then run `./install.sh` again.
- **Something looks wrong:** messages are logged to `~/.claude/swiftbar-claudecode-minimal/plugin.log`, for example when Claude Code's session registry changes format.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md): `tests/lint.sh`, `tests/run.sh` and `tests/run.sh --bench`.

## Roadmap

1. **Core**: hooks, state files, menu bar and dropdown, dead-session cleanup
2. **Accuracy**: registry override, interrupt and approved-tool detection, staleness, instant refresh
3. **Reach**: herdr focus on click, session-type filters, subagent rows, Settings menu
4. **Release**: Claude Code plugin packaging, install scripts, tests, v1.0
5. **Later**: focus support for VS Code and other terminals

## License

[MIT](LICENSE)
