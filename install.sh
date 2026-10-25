#!/bin/sh
# Install Minimalist Claude Code Statusbar without the Claude Code plugin system:
#   1. adds the state hook to ~/.claude/settings.json (existing hooks are kept as they are),
#   2. links the SwiftBar plugin into SwiftBar's plugin folder.
# Run it again at any time; it never adds anything twice. Undo with ./uninstall.sh.
#
# Overrides: CLAUDE_STATUSBAR_SETTINGS (settings file), CLAUDE_STATUSBAR_SWIFTBAR_DIR (plugin folder).

set -u

repo="$(cd "$(dirname "$0")" && pwd)" || exit 1
# shellcheck source=lib/common.sh
. "$repo/lib/common.sh" || exit 1

# Every hook entry we add ends with this, so uninstall.sh can find exactly ours.
MARKER='# swiftbar-claudecode-minimal'
HOOK_CMD="'$repo/hooks/state-hook.sh' $MARKER"
PLUGIN_NAME=swiftbar-claudecode-minimal.5s.sh

JQ="$(find_jq)"
if [ -z "$JQ" ]; then
  echo "Minimalist Claude Code Statusbar needs jq. Install it with: brew install jq" >&2
  exit 1
fi

settings="${CLAUDE_STATUSBAR_SETTINGS:-$HOME/.claude/settings.json}"

# --- Hooks ----------------------------------------------------------------

mkdir -p "$(dirname "$settings")" || exit 1
if [ -e "$settings" ]; then
  if ! "$JQ" -e 'type == "object"' "$settings" >/dev/null 2>&1; then
    echo "Not changing $settings: it isn't a valid JSON object." >&2
    exit 1
  fi
  backup="$settings.bak-swiftbar-claudecode-minimal-$(date +%Y%m%d-%H%M%S)"
  cp -p "$settings" "$backup" || exit 1
  echo "Backed up $settings to $backup"
else
  printf '{}\n' > "$settings"
fi

events="$("$JQ" -r '.hooks | keys[]' "$repo/hooks/hooks.json")"

# Append one marked entry per event that doesn't have ours yet; leave the rest alone.
"$JQ" --arg cmd "$HOOK_CMD" --arg marker "$MARKER" --arg events "$events" '
  ($events | split("\n") | map(select(. != ""))) as $evs
  | reduce $evs[] as $e (.;
      if any(.hooks[$e][]?.hooks[]?; (.command // "") | endswith($marker)) then .
      else .hooks[$e] = ((.hooks[$e] // []) + [{hooks: [{type: "command", command: $cmd, async: true, timeout: 10}]}])
      end)
' "$settings" > "$settings.tmp.$$" && mv "$settings.tmp.$$" "$settings" || {
  rm -f "$settings.tmp.$$"
  echo "Could not update $settings" >&2
  exit 1
}
echo "Hooks registered in $settings"

# --- SwiftBar -------------------------------------------------------------

plugin_dir="${CLAUDE_STATUSBAR_SWIFTBAR_DIR:-$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null)}"
if [ -z "$plugin_dir" ] && [ -t 0 ]; then
  printf 'SwiftBar has no plugin folder yet. Folder to use (empty to skip): '
  read -r plugin_dir
fi
plugin_dir="$(ca_expand_home "$plugin_dir")"

if [ -z "$plugin_dir" ]; then
  echo "Skipped the SwiftBar link. Later, run:"
  echo "  ln -s '$repo/swiftbar/$PLUGIN_NAME' <SwiftBar plugin folder>/"
else
  mkdir -p "$plugin_dir" || exit 1
  ln -sf "$repo/swiftbar/$PLUGIN_NAME" "$plugin_dir/$PLUGIN_NAME" || exit 1
  echo "Linked $plugin_dir/$PLUGIN_NAME"
fi

echo "Done. New Claude Code sessions will show up in the menu bar."
