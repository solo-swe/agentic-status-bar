#!/bin/sh
# Undo install.sh: removes only the hook entries it added and the SwiftBar link.
# Asks before deleting state files and config (or pass --purge to delete them).
#
# Overrides: CLAUDE_AGENTS_SETTINGS (settings file), CLAUDE_AGENTS_SWIFTBAR_DIR (plugin folder).

set -u

repo="$(cd "$(dirname "$0")" && pwd)" || exit 1
# shellcheck source=lib/common.sh
. "$repo/lib/common.sh" || exit 1

MARKER='# claude-agents'
PLUGIN_NAME=claude-agents.5s.sh

purge=0
[ "${1:-}" = "--purge" ] && purge=1

JQ="$(find_jq)"
if [ -z "$JQ" ]; then
  echo "claude-agents needs jq. Install it with: brew install jq" >&2
  exit 1
fi

# --- Hooks ----------------------------------------------------------------

settings="${CLAUDE_AGENTS_SETTINGS:-$HOME/.claude/settings.json}"
if [ -e "$settings" ]; then
  if ! "$JQ" -e 'type == "object"' "$settings" >/dev/null 2>&1; then
    echo "Not changing $settings: it isn't a valid JSON object." >&2
    exit 1
  fi
  backup="$settings.bak-claude-agents-$(date +%Y%m%d-%H%M%S)"
  cp -p "$settings" "$backup" || exit 1
  echo "Backed up $settings to $backup"

  # Drop our entries, then any group or event array that only held ours.
  "$JQ" --arg marker "$MARKER" '
    def ours: (.command // "") | endswith($marker);
    if (.hooks | type) != "object" then .
    else
      .hooks |= with_entries(
        .value |= (
          if type != "array" then .
          else map(
              if (.hooks | type) == "array" and any(.hooks[]; ours)
              then .hooks |= map(select(ours | not)) | select(.hooks | length > 0)
              else . end)
          end)
        | select((.value | type) != "array" or (.value | length) > 0))
      | if .hooks == {} then del(.hooks) else . end
    end
  ' "$settings" > "$settings.tmp.$$" && mv "$settings.tmp.$$" "$settings" || {
    rm -f "$settings.tmp.$$"
    echo "Could not update $settings" >&2
    exit 1
  }
  echo "Removed claude-agents hooks from $settings"
fi

# --- SwiftBar -------------------------------------------------------------

plugin_dir="${CLAUDE_AGENTS_SWIFTBAR_DIR:-$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null)}"
plugin_dir="$(ca_expand_home "$plugin_dir")"
link="$plugin_dir/$PLUGIN_NAME"
if [ -n "$plugin_dir" ] && [ -L "$link" ] && [ "$(readlink "$link")" = "$repo/swiftbar/$PLUGIN_NAME" ]; then
  rm -f "$link"
  echo "Removed $link"
fi

# --- State and config -----------------------------------------------------

load_config
config="$(ca_config_file)"
if [ "$purge" = 0 ] && [ -t 0 ]; then
  printf 'Also delete %s and %s? [y/N] ' "$cfg_state_dir" "$config"
  read -r answer
  case "$answer" in
    y | Y | yes) purge=1 ;;
  esac
fi
if [ "$purge" = 1 ]; then
  rm -rf "$cfg_state_dir"
  rm -f "$config"
  rmdir "$(dirname "$config")" 2>/dev/null
  echo "Deleted $cfg_state_dir and $config"
fi

echo "Done."
