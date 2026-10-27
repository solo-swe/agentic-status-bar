# Agentic Status Bar

A macOS menu-bar app that shows, in one menu-bar item, whether any running
[Claude Code](https://claude.com/claude-code) agent needs you, and notifies you when one has been waiting on you for
a few seconds.

> **Status: pre-release.** See the [PRD](doc/PRD.md) for the full design.

<!-- Screenshots: doc/screenshots/waiting.png, idle.png, popover.png, settings.png -->

## What it shows

The menu-bar item shows one icon for the most urgent state across all sessions, with the number of sessions in that
state. States are checked top to bottom, and the first that applies wins:

| Icon                              | Color      | Number          | Meaning                                                                   |
| --------------------------------- | ---------- | --------------- | ------------------------------------------------------------------------- |
| Warning triangle                  | Orange (yellow in dark mode) | All sessions | Some state files couldn't be read (see Troubleshooting)                   |
| Filled exclamation circle         | Red        | Waiting         | An agent is waiting on a permission prompt or a question                  |
| `zzz`                             | Orange (yellow in dark mode) | Idle | An agent has finished and is waiting for your next prompt                 |
| Question mark in a circle         | Gray       | Stale           | A busy agent has shown no activity for longer than the stale threshold    |
| Sparkle                           | Dim gray   | All sessions    | All agents are working, or waiting on their own subagents; nothing needs you |
| Bell with a slash, no number      | Gray       | —               | Every session is in a muted project                                       |
| Sparkle, no number                | Very faint | —               | No Claude Code sessions running                                           |

Because only the most urgent state is shown, a red `1` can hide idle sessions behind it; the session list shows
every session with its own state. The icons never animate. Each icon and its number share the state's color, in the menu
bar and on the session's row. Hovering the item says what it means ("2 waiting on you").

Clicking the item opens the session list, most urgent first. Each row starts with the same icon and color as the
menu bar uses for its state (drawn here as `!`, `z`, `?`, `✦` and `⌛`):

```
! api-gateway — Add rate limiting to auth routes   permission  2m
z web-dashboard — Fix flaky login test             idle        14m
? data-pipeline — Refactor CSV parser              no activity 41m
✦ docs-site — Migrate to the new theme             working     30s
⌛ search-index — Rebuild the ranking              waiting on 2 subagents  3m
    ↳ Explore                                                  3m
    ↳ Plan                                                     1m
Quit                                                       ? ⓘ ⚙
```

At the bottom, **?** opens the in-app Help (what each symbol means, in your theme's colors), **ⓘ** the About
window and the gear Settings.

A session whose subagents are still running, after its own turn ended or while it waits in its Agent tool, shows an
hourglass and `waiting on N subagents`. In the menu bar it counts as working, not idle. Background subagents that
pause to wait on their own work stay listed until Claude Code reports them finished.

Row titles come from the herdr terminal title, a session name you gave the session, or the first prompt, in that
order.

If a session runs in a [herdr](https://herdr.dev) pane, clicking its row jumps to that pane. Every row also has a
menu (the `…` button on hover, or a right-click) to copy the session ID or working directory, open the folder in
Finder, reveal the transcript, focus the session, or mute its project. Support for other tools (VS Code, other
terminals) is planned.

### Muting a project

Not working on a project today? Its idle `zzz` doesn't have to sit in the menu bar. A row's menu has **Mute project
for 1 hour** and **Mute project for today** (until midnight). A mute covers every session in that project folder,
including ones you start later:

- muted sessions don't count in the menu bar and move to the bottom of the list with a gray bell-with-slash icon and
  `muted until 18:40` or `muted today`;
- a muted session that is waiting on a permission prompt or a question still turns the menu bar red, and still
  notifies you;
- sending a prompt in a muted project unmutes it;
- **Unmute project** in the row's menu, or **Unmute all projects** at the bottom of the list, ends a mute early.

### Notifications

When a session has been waiting on you (a permission prompt or a question) for 10 seconds, the app sends one
notification, also for muted projects. It is withdrawn when the session moves on. **Focus** jumps to the session
(clicking the notification does too), and **Mute project for 1 hour** quiets it. macOS asks for permission the first
time. **Settings › Notifications** turns them off, adds notifications for idle sessions, changes the delay (5, 10, 30
or 60 seconds) and the sound, and sends a test notification.

## How it works

1. **Claude Code hooks** (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`,
   `SessionEnd`, subagent events) run `asb hook`, a small command-line tool that comes with the app. It writes one
   JSON state file per session to `~/.claude/agentic-status-bar/` ([the format](doc/state-file-schema.md)).
2. **The app** watches that folder, and checks every 5 seconds. It reads the files and corrects states the hooks
   can't see:
   - removes sessions whose process has exited,
   - shows sessions as idle after Esc or a denied permission,
   - shows sessions running an approved long tool as busy, not waiting,
   - uses Claude Code's own session registry when it is present and newer,
   - marks anything else that has gone quiet for too long as `?` rather than guessing.

Everything stays on your machine. Hooks run async and always exit 0, so they can't slow down or break Claude Code;
`asb hook` takes about 9 ms.

## Requirements

- macOS 14 or later
- Claude Code with hooks support
- Optional: [herdr](https://herdr.dev) for jumping to the exact pane
- To build it yourself: Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Install

Download the DMG from the [Releases](https://github.com/solo-swe/agentic-status-bar/releases) page: it is signed
and notarized by Apple. Builds run on Apple silicon Macs. Or build the app yourself:

```sh
git clone https://github.com/solo-swe/agentic-status-bar.git ~/code/agentic-status-bar
cd ~/code/agentic-status-bar
scripts/package.sh 0.2.1
open dist/agentic-status-bar-0.2.1.dmg
```

Drag **Agentic Status Bar** to Applications and open it. On first launch it explains what it changes and offers
**Install Hooks**, which:

- copies its `asb` tool to `~/Library/Application Support/agentic-status-bar/bin/asb`, so the hooks keep working
  wherever the app lives (the app keeps that copy up to date when it updates);
- adds the hooks to `~/.claude/settings.json`, after backing it up, leaving your other settings and hooks exactly as
  they are;
- moves state and config from the older SwiftBar plugin (Minimalist Claude Code Statusbar), replaces its hooks and
  removes its "start SwiftBar at login" item. If you used that plugin, also run `asb install` once (see below): it
  removes the plugin's link from SwiftBar's plugin folder.

Hooks load when a session starts, so restart running Claude Code sessions, or wait for their next event (sessions
that were already running fill in their details then).

**Settings › General › Start at login** opens the app when you log in.

## Updates

The app checks for updates once a day and offers new versions as they are released; **Check for Updates…** in the
app menu, or **Check for Updates** in Settings › General, checks right away. Turn off **Check for updates automatically**
in Settings › General to check only by hand. Updates are downloaded from this repository's GitHub releases and are
signed: the app installs only an update signed with the project's key. Builds you make yourself don't update.

## Settings

The gear at the bottom of the list opens Settings:

- **General:** start at login; updates; install or remove the Claude Code hooks; which session types to show
  (interactive, headless `claude -p`, IDE and desktop, subagents); when a quiet session counts as "no activity" (10,
  30 or 60 minutes, or never); Claude Code's session registry; prompt previews as row titles; the config file.
- **Appearance:** the theme (default, monochrome or high contrast), and each state's symbol and color, picked from a
  set (each color has a shade for a light and a dark menu bar). Other SF Symbols and colors can be set in the config
  file.
- **Notifications:** see above.

Settings are stored in `~/.config/agentic-status-bar/config` (`key=value`), which `asb` reads too:

| Key                                                               | Default                                 | Meaning                                                                  |
| ----------------------------------------------------------------- | --------------------------------------- | ------------------------------------------------------------------------ |
| `show_interactive`, `show_headless`, `show_subagents`, `show_ide` | `1`                                     | Which session types to show (`show_ide` covers IDE and desktop sessions) |
| `stale_minutes`                                                   | `30`                                    | Minutes without activity before a busy session shows `?`; `0` = off      |
| `use_registry`                                                    | `1`                                     | Use Claude Code's session registry when it is newer                      |
| `theme`                                                           | `default`                               | `default`, `monochrome` or `high_contrast`                               |
| `icon_<state>`, `color_<state>`                                   | from the theme                          | Override one state's SF Symbol name, and its `#RRGGBB` color or `light,dark` pair. States: `waiting`, `idle`, `uncertain`, `busy`, `subagents`, `muted`, `none`, `warning` |
| `icon`                                                            | from the theme                          | Older shortcut: SF Symbol for both the busy and empty icon               |
| `store_prompt_preview`                                            | `1`                                     | Keep an 80-character prompt preview for row titles                       |
| `notify_waiting`, `notify_idle`                                   | `1`, `0`                                | Notify when a session waits on you, or goes idle                         |
| `notify_delay_seconds`                                            | `10`                                    | How long before the notification                                         |
| `notify_sound`                                                    | `1`                                     | Play a sound with notifications                                          |
| `state_dir`                                                       | `~/.claude/agentic-status-bar`          | Where hooks write state files                                            |

For example, to show idle sessions as a blue moon:

```
icon_idle=moon.zzz
color_idle=#0040DD,#64D2FF
```

## The `asb` command

The app's `asb` tool also works on its own, for scripts and for checking what the app sees. It is at
`~/Library/Application Support/agentic-status-bar/bin/asb` once the hooks are installed, or `.build/release/asb`
after `swift build -c release` in a clone.

| Command | What it does |
| --- | --- |
| `asb snapshot --json --pretty` | The sessions and menu-bar state exactly as the app shows them ([the format](doc/snapshot-schema.md)) |
| `asb install` | Installs the hooks (as the app's **Install Hooks** does) and removes the old SwiftBar plugin's link; safe to run again |
| `asb uninstall` | Removes the hooks and the copy of `asb`; asks before deleting state and config (`--purge` deletes them) |
| `asb action <name> <session ID>` | Runs a row action: `focus`, `mute-hour`, `mute-today`, `unmute`, `copy-id`, `copy-cwd`, `open-folder`, `reveal-transcript`; `asb action unmute-all` takes no session |
| `asb hook` | The hook itself: reads a Claude Code hook payload on stdin |

## Uninstall

**Settings › General › Remove Hooks…** (or `asb uninstall`) removes the hooks from `~/.claude/settings.json` (after a
backup) and the copy of `asb`; state and config stay. Turn off **Start at login**, quit the app (**Quit** at the
bottom of the session list), and move it to the Trash.

## Troubleshooting

- **No sessions show up:** check **Settings › General** says the hooks are installed. A session started before the
  hooks were installed appears after its next event; send it a prompt, or restart it.
- **Warning triangle:** a state file in `~/.claude/agentic-status-bar/` is corrupt or from a newer version. Delete
  the file or update; a running session writes a fresh one on its next event.
- **No notifications:** allow Agentic Status Bar in System Settings › Notifications, then use **Send Test
  Notification** in Settings.
- **Something looks wrong:** messages are logged to `~/.claude/agentic-status-bar/plugin.log`, for example when
  Claude Code's session registry changes format. `asb snapshot --json --pretty` shows exactly what the list is built
  from.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Roadmap

1. **Done:** hooks, state files, menu bar and session list, accuracy checks, herdr focus, filters, mutes, themes
2. **Done:** the move from shell and jq to Swift (`asb`), and from a SwiftBar plugin to a standalone app with
   notifications
3. **Done:** signed, notarized releases with automatic updates
4. **Next:** in-app help, Homebrew
5. **Later:** atm integration, focus support for VS Code and other terminals

## License

[MIT](LICENSE)
