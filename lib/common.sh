# shellcheck shell=sh disable=SC2034
# (SC2034: the cfg_* variables are read by the scripts that source this file.)
# Shared helpers for the claude-agents hook and SwiftBar plugin. Source it; don't run it.
#
# Config values are exposed as cfg_<key> variables after load_config.

CA_CONFIG_KEYS="show_interactive show_headless show_subagents show_ide stale_minutes use_registry instant_refresh icon store_prompt_preview state_dir"

ca_config_file() {
  printf '%s\n' "${CLAUDE_AGENTS_CONFIG:-$HOME/.config/claude-agents/config}"
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
  cfg_state_dir="$HOME/.claude/swiftbar-agents"

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
  if [ -n "${CLAUDE_AGENTS_STATE_DIR:-}" ]; then
    cfg_state_dir="$CLAUDE_AGENTS_STATE_DIR"
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
find_jq() {
  for _ca_jq in /usr/bin/jq /opt/homebrew/bin/jq /usr/local/bin/jq; do
    if [ -x "$_ca_jq" ]; then
      printf '%s\n' "$_ca_jq"
      return 0
    fi
  done
  command -v jq 2>/dev/null
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
