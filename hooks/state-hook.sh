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
changed=0
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
  changed=1
}

# SwiftBar refreshes a plugin when this URL is opened.
REFRESH_URL='swiftbar://refreshplugin?name=claude-agents'
POKE_INTERVAL_MS=500

# poke_swiftbar — asks SwiftBar to refresh now, at most once per POKE_INTERVAL_MS.
poke_swiftbar() {
  [ "$cfg_instant_refresh" = 1 ] || return 0
  _stamp="$cfg_state_dir/.last-poke"
  _now="$(now_ms)"
  _last="$(cat "$_stamp" 2>/dev/null)"
  case "$_last" in
    '' | *[!0-9]*) _last=0 ;;
  esac
  [ $((_now - _last)) -ge "$POKE_INTERVAL_MS" ] || return 0
  printf '%s\n' "$_now" | atomic_write "$_stamp"
  open -g "$REFRESH_URL" &
}

# find_claude_pid — walks up from our parent to the first claude process and
# prints its PID. Prints nothing if none is found within a few levels.
# CLAUDE_AGENTS_PARENT_PID overrides the starting point (used by tests).
find_claude_pid() {
  _pid="${CLAUDE_AGENTS_PARENT_PID:-$PPID}"
  _depth=0
  while [ -n "$_pid" ] && [ "$_pid" -gt 1 ] && [ "$_depth" -lt 6 ]; do
    _comm="$(ps -o comm= -p "$_pid" 2>/dev/null)"
    case "$(basename "$_comm")" in
      claude)
        printf '%s\n' "$_pid"
        return 0
        ;;
      node)
        # npm installs run Claude Code under node.
        case "$(ps -o args= -p "$_pid" 2>/dev/null)" in
          *claude*)
            printf '%s\n' "$_pid"
            return 0
            ;;
        esac
        ;;
    esac
    _pid="$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ')"
    _depth=$((_depth + 1))
  done
}

# session_kind PID — interactive, headless, ide or desktop.
session_kind() {
  case "${CLAUDE_CODE_ENTRYPOINT:-}" in
    sdk-*) echo headless; return ;;
    *vscode* | *jetbrains* | *ide*) echo ide; return ;;
    *desktop*) echo desktop; return ;;
  esac
  if [ -n "$1" ]; then
    case " $(ps -o args= -p "$1" 2>/dev/null) " in
      *" -p "* | *" --print "*) echo headless; return ;;
    esac
  fi
  echo interactive
}

on_session_start() {
  _cpid="$(find_claude_pid)"
  _pstart=""
  if [ -n "$_cpid" ]; then
    _pstart="$(ps -o lstart= -p "$_cpid" 2>/dev/null | sed 's/^ *//;s/ *$//')"
  fi
  _source="$(field '.source')"

  write_state '
    .cwd = $cwd
    | .transcriptPath = $transcript
    | .kind = $kind
    | (if $pid != "" then .pid = ($pid | tonumber) | .procStart = $pstart else del(.pid, .procStart) end)
    | (if $pane != "" then .herdrPane = $pane else del(.herdrPane) end)
    | (if $bundle != "" then .termBundleId = $bundle else del(.termBundleId) end)
    | (if $source == "compact" and .state != null then . else .state = "idle" | del(.reason, .message) end)
  ' \
    --arg cwd "$(field '.cwd')" \
    --arg transcript "$(field '.transcript_path')" \
    --arg kind "$(session_kind "$_cpid")" \
    --arg pid "$_cpid" \
    --arg pstart "$_pstart" \
    --arg pane "${HERDR_PANE_ID:-}" \
    --arg bundle "${__CFBundleIdentifier:-}" \
    --arg source "$_source"

  # A claude process runs one session at a time: drop older files for the same PID
  # (e.g. the session before a /clear).
  if [ -n "$_cpid" ]; then
    for _f in "$cfg_state_dir"/*.json; do
      [ -f "$_f" ] || continue
      [ "$_f" = "$state_file" ] && continue
      if [ "$("$JQ" -r '.pid // empty' "$_f" 2>/dev/null)" = "$_cpid" ]; then
        rm -f "$_f"
      fi
    done
  fi
}
# Prompts that start with this are background-task results, not something the user typed.
TASK_NOTIFICATION_PREFIX='<task-notification>'

on_user_prompt_submit() {
  write_state '
    .state = "busy"
    | del(.reason, .message)
    | if $store == "1" and ($prompt | startswith($skip) | not) and ($prompt != "")
      then .promptPreview = ($prompt | gsub("\\s+"; " ") | ltrimstr(" ") | .[0:80])
      elif $store != "1" then del(.promptPreview)
      else . end
  ' \
    --arg prompt "$(field '.prompt')" \
    --arg skip "$TASK_NOTIFICATION_PREFIX" \
    --arg store "$cfg_store_prompt_preview"
}

on_pre_tool_use() {
  write_state '.state = "busy" | del(.reason, .message) | .lastTool = $tool' \
    --arg tool "$(field '.tool_name')"
}

on_post_tool_use() {
  write_state '.state = "busy" | del(.reason, .message)'
}
on_notification() {
  _type="$(field '.notification_type')"
  _message="$(field '.message')"
  # Older payloads may lack notification_type: fall back to the message text.
  if [ -z "$_type" ]; then
    case "$_message" in
      *"needs your permission"*) _type=permission_prompt ;;
      *"waiting for your input"*) _type=idle_prompt ;;
    esac
  fi

  case "$_type" in
    permission_prompt)
      # AskUserQuestion questions also arrive as permission prompts.
      write_state '
        .state = "waiting"
        | .reason = (if .lastTool == "AskUserQuestion" then "question" else "permission" end)
        | .message = $message
      ' --arg message "$_message"
      ;;
    elicitation_dialog)
      write_state '.state = "waiting" | .reason = "question" | .message = $message' \
        --arg message "$_message"
      ;;
    idle_prompt)
      write_state '.state = "idle" | del(.reason, .message)'
      ;;
  esac
}

on_stop() {
  write_state '.state = "idle" | del(.reason, .message)'
}
on_subagent_start() { :; }
on_subagent_stop() { :; }
# A late async event can recreate the file after this; the plugin's liveness
# check (C1) removes it once the claude process is gone.
on_session_end() {
  lock
  rm -f "$state_file"
  unlock
  changed=1
}

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

  [ "$changed" = 1 ] && poke_swiftbar
}

main
exit 0
