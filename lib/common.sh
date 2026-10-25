# shellcheck shell=sh disable=SC2034
# (SC2034: the cfg_* variables are read by the scripts that source this file.)
# Shared helpers for the Minimalist Claude Code Statusbar hook and SwiftBar plugin. Source it; don't run it.
#
# Config values are exposed as cfg_<key> variables after load_config.

CA_CONFIG_KEYS="show_interactive show_headless show_subagents show_ide stale_minutes use_registry instant_refresh icon store_prompt_preview state_dir"

ca_config_file() {
  printf '%s\n' "${CLAUDE_STATUSBAR_CONFIG:-$HOME/.config/swiftbar-claudecode-minimal/config}"
}

# ca_is_key KEY — true if KEY is a known config key.
ca_is_key() {
  case " $CA_CONFIG_KEYS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# ca_valid_value VALUE — values are plain words or paths; anything with shell
# metacharacters is rejected.
ca_valid_value() {
  case "$1" in
    *[!A-Za-z0-9_./~-]*) return 1 ;;
  esac
  return 0
}

# ca_expand_home PATH — expands a leading ~ to $HOME.
ca_expand_home() {
  # shellcheck disable=SC2088 # matching a literal ~ on purpose
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

load_config() {
  cfg_show_interactive=1
  cfg_show_headless=1
  cfg_show_subagents=1
  cfg_show_ide=1
  cfg_stale_minutes=30
  cfg_use_registry=1
  cfg_instant_refresh=1
  cfg_icon=sparkle
  cfg_store_prompt_preview=1
  cfg_state_dir="$HOME/.claude/swiftbar-claudecode-minimal"

  _ca_file="$(ca_config_file)"
  if [ -r "$_ca_file" ]; then
    while IFS='=' read -r _ca_key _ca_value || [ -n "$_ca_key" ]; do
      case "$_ca_key" in
        ''|'#'*) continue ;;
      esac
      ca_is_key "$_ca_key" || continue
      ca_valid_value "$_ca_value" || continue
      # The key is from the fixed list above, so this eval only assigns.
      eval "cfg_$_ca_key=\$_ca_value"
    done < "$_ca_file"
  fi

  # The environment wins over the config file (used by tests and custom setups).
  if [ -n "${CLAUDE_STATUSBAR_STATE_DIR:-}" ]; then
    cfg_state_dir="$CLAUDE_STATUSBAR_STATE_DIR"
  fi
  cfg_state_dir="$(ca_expand_home "$cfg_state_dir")"
}

# set_config KEY VALUE — sets one key in the config file, keeping the others.
set_config() {
  ca_is_key "$1" || return 1
  ca_valid_value "$2" || return 1
  _ca_file="$(ca_config_file)"
  mkdir -p "$(dirname "$_ca_file")" || return 1
  {
    if [ -r "$_ca_file" ]; then
      grep -v "^$1=" "$_ca_file"
    fi
    printf '%s=%s\n' "$1" "$2"
  } | atomic_write "$_ca_file"
}

# now_ms — milliseconds since the epoch.
now_ms() {
  perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'
}

# atomic_write FILE — writes stdin to FILE via a temp file in the same directory.
atomic_write() {
  _ca_tmp="$1.tmp.$$"
  if cat > "$_ca_tmp" && mv -f "$_ca_tmp" "$1"; then
    return 0
  fi
  rm -f "$_ca_tmp"
  return 1
}

# find_jq — prints the path of jq, or nothing if it isn't installed.
# CLAUDE_STATUSBAR_JQ, when set, is the only candidate (used by tests).
find_jq() {
  if [ -n "${CLAUDE_STATUSBAR_JQ+set}" ]; then
    [ -x "$CLAUDE_STATUSBAR_JQ" ] && printf '%s\n' "$CLAUDE_STATUSBAR_JQ"
    return 0
  fi
  for _ca_jq in /usr/bin/jq /opt/homebrew/bin/jq /usr/local/bin/jq; do
    if [ -x "$_ca_jq" ]; then
      printf '%s\n' "$_ca_jq"
      return 0
    fi
  done
  command -v jq 2>/dev/null
}

# find_herdr — prints the path of herdr, or nothing if it isn't installed.
# CLAUDE_STATUSBAR_HERDR, when set, is the only candidate (used by tests).
find_herdr() {
  if [ -n "${CLAUDE_STATUSBAR_HERDR+set}" ]; then
    [ -x "$CLAUDE_STATUSBAR_HERDR" ] && printf '%s\n' "$CLAUDE_STATUSBAR_HERDR"
    return 0
  fi
  for _ca_herdr in /opt/homebrew/bin/herdr /usr/local/bin/herdr; do
    if [ -x "$_ca_herdr" ]; then
      printf '%s\n' "$_ca_herdr"
      return 0
    fi
  done
  command -v herdr 2>/dev/null
}

# run_with_timeout SECONDS COMMAND... — runs COMMAND, killing it after SECONDS.
# Returns COMMAND's status (non-zero if it was killed).
run_with_timeout() {
  _ca_secs="$1"
  shift
  "$@" &
  _ca_pid=$!
  ( sleep "$_ca_secs"; kill "$_ca_pid" 2>/dev/null ) &
  _ca_watcher=$!
  wait "$_ca_pid"
  _ca_status=$?
  kill "$_ca_watcher" 2>/dev/null
  wait "$_ca_watcher" 2>/dev/null
  return "$_ca_status"
}

# log_once KEY MESSAGE — appends MESSAGE to plugin.log unless KEY was logged before.
# Call load_config first.
log_once() {
  _ca_log="$cfg_state_dir/plugin.log"
  if [ -r "$_ca_log" ] && grep -q "^\[$1\] " "$_ca_log"; then
    return 0
  fi
  mkdir -p "$cfg_state_dir" 2>/dev/null
  printf '[%s] %s %s\n' "$1" "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$2" >> "$_ca_log"
}
