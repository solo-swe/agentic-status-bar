# claude-agents

A minimal [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that shows, in one menu-bar item, whether any running [Claude Code](https://claude.com/claude-code) agent needs you.

> **Status: design phase.** Nothing is implemented yet. The install and usage sections below describe the planned v1. See the [PRD](doc/PRD.md) for the full design.

## What it shows

| Menu bar | Meaning |
| --- | --- |
| Red icon + count | An agent is waiting on a permission prompt or a question |
| Yellow icon + count | An agent has finished and is waiting for your next prompt |
| Gray icon + `?` | An agent's state is uncertain (no activity for longer than the stale threshold) |
| Dimmed icon + count | All agents are working; nothing needs you |
| Faint icon | No Claude Code sessions running |

The dropdown lists every session, most urgent first:

```
● api-gateway — Add rate limiting to auth routes   permission · 2m
● web-dashboard — Fix flaky login test             idle · 14m
○ docs-site — Migrate to the new theme             working · 30s
    ↳ subagent: Explore                            working · 12s
---
Show: ✓ Interactive  ✓ Headless  ✓ Subagents  ✓ IDE/Desktop
Settings… · Refresh
```

If a session runs in a [herdr](https://herdr.dev) pane, clicking its row jumps to that pane. Without herdr, clicking does nothing harmful, and each row's submenu still lets you copy the session ID or open its folder. Support for other tools (VS Code, other terminals) is planned.

## How it works

1. **Claude Code hooks** (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SessionEnd`, subagent events) write one small JSON state file per session to `~/.claude/swiftbar-agents/`.
2. **The SwiftBar plugin** reads those files every 5 seconds, or right away when a hook pokes it, and corrects states the hooks cannot see:
   - removes sessions whose process has died,
   - shows Esc-interrupted sessions as idle,
   - shows sessions running an approved long tool as busy, not waiting,
   - uses Claude Code's own session registry when it is present and newer,
   - marks anything else that has gone quiet for too long as `?` rather than guessing.

Everything stays on your machine. Hooks run async and always exit 0, so they can't slow down or break Claude Code.

## Requirements

- macOS 15 or later (ships `/usr/bin/jq`; on older macOS, `brew install jq`)
- [SwiftBar](https://github.com/swiftbar/SwiftBar) 2.x
- Claude Code with hooks support
- Optional: [herdr](https://herdr.dev) for jumping to the exact pane

## Install (planned)

**As a Claude Code plugin (recommended)** — registers the hooks without editing your `settings.json`:

```sh
# inside Claude Code
/plugin install claude-agents
```

Then link the SwiftBar script into your SwiftBar plugin folder:

```sh
ln -s "$PWD/swiftbar/claude-agents.5s.sh" "$(defaults read com.ameba.SwiftBar PluginDirectory)/"
```

**Without the plugin system:**

```sh
./install.sh     # backs up ~/.claude/settings.json, appends hooks, links the SwiftBar script
./uninstall.sh   # removes only the entries install.sh added
```

Your existing hooks are left in place.

## Configuration

Settings live in `~/.config/claude-agents/config` and can be changed from the dropdown's **Show** and **Settings** items.

| Key | Default | Meaning |
| --- | --- | --- |
| `show_interactive`, `show_headless`, `show_subagents`, `show_ide` | `1` | Which session types to show |
| `stale_minutes` | `30` | Minutes without activity before a busy session shows `?`; `0` = off |
| `use_registry` | `1` | Use Claude Code's session registry when it is newer |
| `instant_refresh` | `1` | Hooks trigger an immediate SwiftBar refresh |
| `icon` | `sparkle` | SF Symbol name for the menu-bar icon |
| `store_prompt_preview` | `1` | Keep an 80-character prompt preview for row titles |

## Roadmap

1. **Core** — hooks, state files, menu bar and dropdown, dead-session cleanup
2. **Accuracy** — registry override, interrupt and approved-tool detection, staleness, instant refresh
3. **Reach** — herdr focus on click, session-type filters, subagent rows, Settings menu
4. **Release** — Claude Code plugin packaging, install scripts, tests, v1.0
5. **Later** — focus support for VS Code and other terminals

## License

MIT (proposed)
