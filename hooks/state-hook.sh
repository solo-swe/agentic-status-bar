#!/bin/sh
# shellcheck source-path=SCRIPTDIR disable=SC2016
# (SC2016: jq programs use $variables inside single quotes on purpose.)
# Minimalist Claude Code Statusbar hook: turns Claude Code hook events into one state file per session
# ($state_dir/<session_id>.json) for the SwiftBar plugin to read.
#
# It must never get in Claude Code's way: no `set -e`, all output discarded,
# every error swallowed, always exit 0. It runs on every tool call, so it keeps
# to two jq calls per event and no other helper processes on the common path.

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
case "$self" in
  */*) hook_dir="${self%/*}" ;;
  *) hook_dir=. ;;
esac
# shellcheck source=../lib/common.sh
. "$hook_dir/../lib/common.sh" || exit 0

lock_dir=""
changed=0
# shellcheck disable=SC2329 # called from traps
cleanup() {
  [ -n "$lock_dir" ] && rmdir "$lock_dir" 2>/dev/null
}
trap 'cleanup; exit 0' HUP INT TERM
trap cleanup EXIT

# parse_payload — reads the hook JSON from stdin into shell variables (event,
# session_id, p_* fields) and started_ms, the event's start in epoch ms. Events
# that start earlier win when async hooks race.
parse_payload() {
  eval "$("$JQ" -r '
    def s($k): (.[$k] // "") | if type == "string" then . else tostring end;
    if type != "object" then empty else
      @sh "event=\(s("hook_event_name"))",
      @sh "session_id=\(s("session_id"))",
      @sh "p_cwd=\(s("cwd"))",
      @sh "p_transcript=\(s("transcript_path"))",
      @sh "p_source=\(s("source"))",
      @sh "p_prompt=\(s("prompt"))",
      @sh "p_tool=\(s("tool_name"))",
      @sh "p_ntype=\(s("notification_type"))",
      @sh "p_message=\(s("message"))",
      @sh "p_agent_id=\(s("agent_id"))",
      @sh "p_agent_type=\(s("agent_type"))",
      "started_ms=\(now * 1000 | floor)"
    end
  ' 2>/dev/null)"
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

# write_state FILTER [JQ ARGS...] — applies FILTER to the current state (as `.`,
# with the previous state also in $old and the time in $now) and writes the
# result atomically. Sets v, sessionId and updatedAt; sets stateSince when the
# state changes. Skipped if the file already has an update newer than this
# event's start. A missing or corrupt file counts as {}.
write_state() {
  _filter="$1"
  shift
  [ -d "$cfg_state_dir" ] || mkdir -p "$cfg_state_dir" || return 1
  lock || return 1
  _program="
    (if type == \"object\" then . else {} end)
    | if (.updatedAt // 0) > \$started then empty
      else (now * 1000 | floor) as \$now
        | . as \$old
        | ($_filter)
        | .v = 1
        | .sessionId = \$sid
        | .updatedAt = \$now
        | if (.state != \$old.state) or (.stateSince == null) then .stateSince = \$now else . end
      end"
  _out=""
  if [ -r "$state_file" ]; then
    _out="$("$JQ" -c --arg sid "$session_id" --argjson started "$started_ms" "$@" "$_program" "$state_file" 2>/dev/null)" \
      || _out="$("$JQ" -n -c --arg sid "$session_id" --argjson started "$started_ms" "$@" "{} | $_program")"
  else
    _out="$("$JQ" -n -c --arg sid "$session_id" --argjson started "$started_ms" "$@" "{} | $_program")"
  fi
  if [ -n "$_out" ] && printf '%s\n' "$_out" > "$state_file.tmp.$$" && mv -f "$state_file.tmp.$$" "$state_file"; then
    changed=1
  fi
  rm -f "$state_file.tmp.$$"
  unlock
}

# SwiftBar refreshes a plugin when this URL is opened.
REFRESH_URL='swiftbar://refreshplugin?name=swiftbar-claudecode-minimal'
POKE_INTERVAL_MS=500

# poke_swiftbar — asks SwiftBar to refresh now, at most once per POKE_INTERVAL_MS.
poke_swiftbar() {
  [ "$cfg_instant_refresh" = 1 ] || return 0
  _stamp="$cfg_state_dir/.last-poke"
  _last=0
  [ -r "$_stamp" ] && read -r _last < "$_stamp"
  case "$_last" in
    '' | *[!0-9]*) _last=0 ;;
  esac
  [ $((started_ms - _last)) -ge "$POKE_INTERVAL_MS" ] || return 0
  printf '%s\n' "$started_ms" > "$_stamp.tmp.$$" && mv -f "$_stamp.tmp.$$" "$_stamp"
  open -g "$REFRESH_URL" &
}

# find_claude_pid — walks up from our parent to the first claude process and
# prints its PID. Prints nothing if none is found within a few levels.
# CLAUDE_STATUSBAR_PARENT_PID overrides the starting point (used by tests).
find_claude_pid() {
  _pid="${CLAUDE_STATUSBAR_PARENT_PID:-$PPID}"
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

  write_state '
    .cwd = $cwd
    | .transcriptPath = $transcript
    | .kind = $kind
    | (if $pid != "" then .pid = ($pid | tonumber) | .procStart = $pstart else del(.pid, .procStart) end)
    | (if $pane != "" then .herdrPane = $pane else del(.herdrPane) end)
    | (if $bundle != "" then .termBundleId = $bundle else del(.termBundleId) end)
    | (if $source == "compact" and .state != null then . else .state = "idle" | del(.reason, .message, .subagents) end)
  ' \
    --arg cwd "$p_cwd" \
    --arg transcript "$p_transcript" \
    --arg kind "$(session_kind "$_cpid")" \
    --arg pid "$_cpid" \
    --arg pstart "$_pstart" \
    --arg pane "${HERDR_PANE_ID:-}" \
    --arg bundle "${__CFBundleIdentifier:-}" \
    --arg source "$p_source"

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
    --arg prompt "$p_prompt" \
    --arg skip "$TASK_NOTIFICATION_PREFIX" \
    --arg store "$cfg_store_prompt_preview"
}

on_pre_tool_use() {
  write_state '.state = "busy" | del(.reason, .message) | .lastTool = $tool' \
    --arg tool "$p_tool"
}

on_post_tool_use() {
  write_state '.state = "busy" | del(.reason, .message)'
}

on_notification() {
  _type="$p_ntype"
  # Older payloads may lack notification_type: fall back to the message text.
  if [ -z "$_type" ]; then
    case "$p_message" in
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
      ' --arg message "$p_message"
      ;;
    elicitation_dialog)
      write_state '.state = "waiting" | .reason = "question" | .message = $message' \
        --arg message "$p_message"
      ;;
    idle_prompt)
      write_state '.state = "idle" | del(.reason, .message)'
      ;;
  esac
}

on_stop() {
  write_state '.state = "idle" | del(.reason, .message)'
}

# Subagents are tracked under the parent session; they never change its state.
on_subagent_start() {
  [ -n "$p_agent_id" ] || return 0
  write_state '
    .state //= "busy"
    | .subagents[$id] = {type: (if $type == "" then "agent" else $type end), since: $now}
  ' --arg id "$p_agent_id" --arg type "$p_agent_type"
}

on_subagent_stop() {
  # An extra SubagentStop with an empty agent_type follows every Stop; it has
  # no matching start.
  [ -n "$p_agent_id" ] && [ -n "$p_agent_type" ] || return 0
  write_state '
    del(.subagents[$id])
    | if (.subagents // {}) == {} then del(.subagents) else . end
  ' --arg id "$p_agent_id"
}

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

  # Set by parse_payload; cleared first so nothing leaks in from the environment.
  event="" session_id="" started_ms=""
  p_cwd="" p_transcript="" p_source="" p_prompt="" p_tool=""
  p_ntype="" p_message="" p_agent_id="" p_agent_type=""
  parse_payload
  [ -n "$event" ] || return 0
  case "$started_ms" in
    '' | *[!0-9]*) return 0 ;;
  esac
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
