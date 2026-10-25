#!/bin/sh
# shellcheck source-path=SCRIPTDIR disable=SC2016
# (SC2016: jq programs use $variables inside single quotes on purpose.)
# claude-agents hook: turns Claude Code hook events into one state file per session
# ($state_dir/<session_id>.json) for the SwiftBar plugin to read.
#
# It must never get in Claude Code's way: no `set -e`, all output discarded,
# every error swallowed, always exit 0.

exec >/dev/null 2>&1

# Resolve our own directory, following symlinks, to find lib/common.sh.
self="$0"
while [ -L "$self" ]; do
  link="$(readlink "$self")"
  case "$link" in
    /*) self="$link" ;;
    *) self="$(dirname "$self")/$link" ;;
  esac
done
hook_dir="$(cd "$(dirname "$self")" && pwd)" || exit 0
# shellcheck source=../lib/common.sh
. "$hook_dir/../lib/common.sh" || exit 0

# Taken first, so events that start earlier win when async hooks race.
started_ms="$(now_ms)"

lock_dir=""
# shellcheck disable=SC2329 # called from traps
cleanup() {
  [ -n "$lock_dir" ] && rmdir "$lock_dir" 2>/dev/null
}
trap 'cleanup; exit 0' HUP INT TERM
trap cleanup EXIT

# field FILTER — runs a jq filter against the payload, printing raw output.
field() {
  printf '%s' "$payload" | "$JQ" -r "$1 // empty" 2>/dev/null
}

# lock / unlock — a per-session mkdir lock, so read-modify-write is not interleaved.
lock() {
  _tries=0
  while ! mkdir "$state_file.lock" 2>/dev/null; do
    _tries=$((_tries + 1))
    [ "$_tries" -ge 50 ] && return 1
    sleep 0.01
  done
  lock_dir="$state_file.lock"
}
unlock() {
  cleanup
  lock_dir=""
}

# read_state — prints the current state object, or {} if missing or corrupt.
read_state() {
  if [ -r "$state_file" ]; then
    "$JQ" -c 'if type == "object" then . else {} end' "$state_file" 2>/dev/null || printf '{}'
  else
    printf '{}'
  fi
}

# write_state FILTER [JQ ARGS...] — applies FILTER to the current state (as `.`,
# with the previous state also in $old) and writes the result atomically. Sets v,
# sessionId and updatedAt; sets stateSince when the state changes. Skipped if the
# file already has an update newer than this event's start.
write_state() {
  _filter="$1"
  shift
  mkdir -p "$cfg_state_dir" || return 1
  lock || return 1
  _current="$(read_state)"
  _newer="$(printf '%s' "$_current" | "$JQ" -r --argjson t "$started_ms" '(.updatedAt // 0) > $t')"
  if [ "$_newer" = "true" ]; then
    unlock
    return 0
  fi
  _now="$(now_ms)"
  printf '%s' "$_current" | "$JQ" -c --arg sid "$session_id" --argjson now "$_now" "$@" "
    . as \$old
    | ($_filter)
    | .v = 1
    | .sessionId = \$sid
    | .updatedAt = \$now
    | if (.state != \$old.state) or (.stateSince == null) then .stateSince = \$now else . end
  " | atomic_write "$state_file"
  unlock
}

on_session_start() { :; }
on_user_prompt_submit() { :; }
on_pre_tool_use() { :; }
on_post_tool_use() { :; }
on_notification() { :; }
on_stop() { :; }
on_subagent_start() { :; }
on_subagent_stop() { :; }
on_session_end() { :; }

main() {
  JQ="$(find_jq)"
  [ -n "$JQ" ] || return 0
  load_config

  payload="$(cat)"
  [ -n "$payload" ] || return 0

  event="$(field '.hook_event_name')"
  session_id="$(field '.session_id')"
  # Session IDs become file names: allow only safe characters.
  case "$session_id" in
    '' | *[!A-Za-z0-9_-]*) return 0 ;;
  esac
  state_file="$cfg_state_dir/$session_id.json"

  case "$event" in
    SessionStart) on_session_start ;;
    UserPromptSubmit) on_user_prompt_submit ;;
    PreToolUse) on_pre_tool_use ;;
    PostToolUse) on_post_tool_use ;;
    Notification) on_notification ;;
    Stop) on_stop ;;
    SubagentStart) on_subagent_start ;;
    SubagentStop) on_subagent_stop ;;
    SessionEnd) on_session_end ;;
  esac
}

main
exit 0
