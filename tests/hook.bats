#!/usr/bin/env bats

setup() {
  load test_helper
  common_setup
  stub_ps
  # The hook's parent is a shell (5000) whose parent is claude (4242).
  add_process 5000 4242 /bin/sh "sh -c state-hook.sh" "Mon Oct 19 09:12:04 2026"
  add_process 4242 1 claude "claude" "Mon Oct 19 09:12:03 2026"
  export CLAUDE_AGENTS_PARENT_PID=5000
  export CLAUDE_CODE_ENTRYPOINT=cli
  export HERDR_PANE_ID=w2:p1
  export __CFBundleIdentifier=com.example.terminal
}
teardown() { common_teardown; }

# --- SessionStart ---------------------------------------------------------

@test "SessionStart writes an idle state with session metadata" {
  run_hook SessionStart
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(state_field .v)" = 1 ]
  [ "$(state_field .sessionId)" = "$FIXTURE_SESSION" ]
  [ "$(state_field .state)" = idle ]
  [ "$(state_field .cwd)" = /Users/alex/code/api-gateway ]
  [ "$(state_field .transcriptPath)" = "/Users/alex/.claude/projects/-Users-alex-code-api-gateway/$FIXTURE_SESSION.jsonl" ]
  [ "$(state_field .kind)" = interactive ]
  [ "$(state_field .pid)" = 4242 ]
  [ "$(state_field .procStart)" = "Mon Oct 19 09:12:03 2026" ]
  [ "$(state_field .herdrPane)" = w2:p1 ]
  [ "$(state_field .termBundleId)" = com.example.terminal ]
  [[ "$(state_field .updatedAt)" =~ ^[0-9]{13}$ ]]
  [ "$(state_field .stateSince)" = "$(state_field .updatedAt)" ]
}

@test "SessionStart finds claude running under node" {
  : > "$TEST_TMP/ps-table"
  add_process 5000 4300 /bin/sh "sh -c state-hook.sh" "x"
  add_process 4300 1 node "node /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js" "Mon Oct 19 08:00:00 2026"
  run_hook SessionStart
  [ "$(state_field .pid)" = 4300 ]
}

@test "SessionStart omits pid when no claude ancestor is found" {
  : > "$TEST_TMP/ps-table"
  add_process 5000 1 /bin/sh "sh" "x"
  run_hook SessionStart
  [ "$(state_field .state)" = idle ]
  [ "$(state_field '.pid // "none"')" = none ]
  [ "$(state_field '.procStart // "none"')" = none ]
}

@test "SessionStart omits herdrPane and termBundleId when not set" {
  unset HERDR_PANE_ID __CFBundleIdentifier
  run_hook SessionStart
  [ "$(state_field '.herdrPane // "none"')" = none ]
  [ "$(state_field '.termBundleId // "none"')" = none ]
}

@test "SessionStart sets kind from the entrypoint and print flag" {
  CLAUDE_CODE_ENTRYPOINT=sdk-cli run_hook SessionStart
  [ "$(state_field .kind)" = headless ]

  CLAUDE_CODE_ENTRYPOINT=claude-vscode run_hook SessionStart
  [ "$(state_field .kind)" = ide ]

  CLAUDE_CODE_ENTRYPOINT=claude-desktop run_hook SessionStart
  [ "$(state_field .kind)" = desktop ]

  : > "$TEST_TMP/ps-table"
  add_process 5000 4242 /bin/sh "sh" "x"
  add_process 4242 1 claude "claude -p --model haiku hello" "Mon Oct 19 09:12:03 2026"
  CLAUDE_CODE_ENTRYPOINT=cli run_hook SessionStart
  [ "$(state_field .kind)" = headless ]
}

@test "SessionStart after compaction keeps the current state" {
  printf '{"v":1,"sessionId":"%s","state":"busy","updatedAt":0,"stateSince":0}\n' "$FIXTURE_SESSION" > "$(state_file)"
  jq '.source = "compact"' "$REPO_ROOT/tests/fixtures/payloads/SessionStart.json" > "$TEST_TMP/compact.json"
  run "$REPO_ROOT/hooks/state-hook.sh" < "$TEST_TMP/compact.json"
  [ "$(state_field .state)" = busy ]
  [ "$(state_field .stateSince)" = 0 ]
}

@test "SessionStart on startup resets an existing state to idle" {
  printf '{"v":1,"sessionId":"%s","state":"busy","reason":"x","updatedAt":0,"stateSince":0}\n' "$FIXTURE_SESSION" > "$(state_file)"
  run_hook SessionStart
  [ "$(state_field .state)" = idle ]
  [ "$(state_field '.reason // "none"')" = none ]
}

@test "SessionStart removes older state files of the same claude process" {
  printf '{"v":1,"sessionId":"old","pid":4242,"state":"busy"}\n' > "$CLAUDE_AGENTS_STATE_DIR/old.json"
  printf '{"v":1,"sessionId":"other","pid":9999,"state":"busy"}\n' > "$CLAUDE_AGENTS_STATE_DIR/other.json"
  run_hook SessionStart
  [ ! -e "$CLAUDE_AGENTS_STATE_DIR/old.json" ]
  [ -e "$CLAUDE_AGENTS_STATE_DIR/other.json" ]
  [ -e "$(state_file)" ]
}

# --- Busy events ----------------------------------------------------------

@test "UserPromptSubmit sets busy and stores the prompt preview" {
  run_hook SessionStart
  run_hook UserPromptSubmit
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(state_field .state)" = busy ]
  [ "$(state_field .promptPreview)" = "Add rate limiting to the auth routes" ]
}

@test "UserPromptSubmit collapses whitespace and truncates the preview to 80 chars" {
  long="$(printf 'line one\n\n  line two %.0s' $(seq 1 20))"
  jq --arg p "$long" '.prompt = $p' "$REPO_ROOT/tests/fixtures/payloads/UserPromptSubmit.json" > "$TEST_TMP/long.json"
  run "$REPO_ROOT/hooks/state-hook.sh" < "$TEST_TMP/long.json"
  preview="$(state_field .promptPreview)"
  [ "${#preview}" -eq 80 ]
  [[ "$preview" == "line one line two line one"* ]]
}

@test "a background task notification keeps the existing preview" {
  run_hook UserPromptSubmit
  run_hook UserPromptSubmit-task-notification
  [ "$(state_field .state)" = busy ]
  [ "$(state_field .promptPreview)" = "Add rate limiting to the auth routes" ]
}

@test "no prompt preview is stored when store_prompt_preview=0" {
  printf 'store_prompt_preview=0\n' > "$CLAUDE_AGENTS_CONFIG"
  run_hook UserPromptSubmit
  [ "$(state_field .state)" = busy ]
  [ "$(state_field '.promptPreview // "none"')" = none ]
}

@test "PreToolUse sets busy, records the tool and clears waiting details" {
  printf '{"v":1,"sessionId":"%s","state":"waiting","reason":"permission","message":"m","updatedAt":0,"stateSince":0}\n' "$FIXTURE_SESSION" > "$(state_file)"
  run_hook PreToolUse
  [ "$(state_field .state)" = busy ]
  [ "$(state_field .lastTool)" = Bash ]
  [ "$(state_field '.reason // "none"')" = none ]
  [ "$(state_field '.message // "none"')" = none ]
}

@test "PostToolUse sets busy and keeps lastTool" {
  run_hook PreToolUse-AskUserQuestion
  run_hook PostToolUse
  [ "$(state_field .state)" = busy ]
  [ "$(state_field .lastTool)" = AskUserQuestion ]
}

@test "stateSince only changes when the state changes" {
  run_hook UserPromptSubmit
  first="$(state_field .stateSince)"
  run_hook PreToolUse
  run_hook PostToolUse
  [ "$(state_field .stateSince)" = "$first" ]
}

# --- Notification and Stop ------------------------------------------------

@test "a permission prompt sets waiting with reason permission" {
  run_hook PreToolUse
  run_hook Notification-permission_prompt
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(state_field .state)" = waiting ]
  [ "$(state_field .reason)" = permission ]
  [ "$(state_field .message)" = "Claude needs your permission" ]
}

@test "a permission prompt after AskUserQuestion sets reason question" {
  run_hook PreToolUse-AskUserQuestion
  run_hook Notification-permission_prompt
  [ "$(state_field .state)" = waiting ]
  [ "$(state_field .reason)" = question ]
}

@test "an elicitation dialog sets waiting with reason question" {
  jq '.notification_type = "elicitation_dialog" | .message = "Server needs input"' \
    "$REPO_ROOT/tests/fixtures/payloads/Notification-permission_prompt.json" > "$TEST_TMP/elicit.json"
  run "$REPO_ROOT/hooks/state-hook.sh" < "$TEST_TMP/elicit.json"
  [ "$(state_field .state)" = waiting ]
  [ "$(state_field .reason)" = question ]
  [ "$(state_field .message)" = "Server needs input" ]
}

@test "an idle prompt sets idle" {
  run_hook Notification-permission_prompt
  run_hook Notification-idle_prompt
  [ "$(state_field .state)" = idle ]
  [ "$(state_field '.reason // "none"')" = none ]
}

@test "without notification_type the message text decides" {
  jq 'del(.notification_type)' "$REPO_ROOT/tests/fixtures/payloads/Notification-permission_prompt.json" > "$TEST_TMP/perm.json"
  run "$REPO_ROOT/hooks/state-hook.sh" < "$TEST_TMP/perm.json"
  [ "$(state_field .state)" = waiting ]
  [ "$(state_field .reason)" = permission ]

  jq 'del(.notification_type)' "$REPO_ROOT/tests/fixtures/payloads/Notification-idle_prompt.json" > "$TEST_TMP/idle.json"
  run "$REPO_ROOT/hooks/state-hook.sh" < "$TEST_TMP/idle.json"
  [ "$(state_field .state)" = idle ]
}

@test "an unknown notification type changes nothing" {
  run_hook UserPromptSubmit
  jq '.notification_type = "auth_success" | .message = "Signed in"' \
    "$REPO_ROOT/tests/fixtures/payloads/Notification-idle_prompt.json" > "$TEST_TMP/other.json"
  run "$REPO_ROOT/hooks/state-hook.sh" < "$TEST_TMP/other.json"
  [ "$(state_field .state)" = busy ]
}

@test "Stop sets idle and clears waiting details" {
  run_hook Notification-permission_prompt
  run_hook Stop
  [ "$(state_field .state)" = idle ]
  [ "$(state_field '.reason // "none"')" = none ]
  [ "$(state_field '.message // "none"')" = none ]
}

# --- SessionEnd -----------------------------------------------------------

@test "SessionEnd deletes the state file" {
  run_hook SessionStart
  [ -e "$(state_file)" ]
  run_hook SessionEnd
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$(state_file)" ]
  [ ! -e "$(state_file).lock" ]
}

@test "SessionEnd succeeds when the state file is already gone" {
  run_hook SessionEnd
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(ls -A "$CLAUDE_AGENTS_STATE_DIR")" ]
}

# --- Robustness -----------------------------------------------------------

@test "hook is silent and exits 0 on bad input" {
  run "$REPO_ROOT/hooks/state-hook.sh" <<< "not json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run "$REPO_ROOT/hooks/state-hook.sh" < /dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "every captured payload runs silently with exit 0" {
  for f in "$REPO_ROOT"/tests/fixtures/payloads/*.json; do
    run "$REPO_ROOT/hooks/state-hook.sh" < "$f"
    [ "$status" -eq 0 ] || { echo "failed: $f"; false; }
    [ -z "$output" ] || { echo "output from $f: $output"; false; }
  done
}

@test "hook does nothing and exits 0 when jq is missing" {
  CLAUDE_AGENTS_JQ=/nonexistent/jq run_hook SessionStart
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$(state_file)" ]
}

@test "hook gives up quietly when the session lock is held" {
  mkdir "$(state_file).lock"
  run_hook SessionStart
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$(state_file)" ]
  [ -d "$(state_file).lock" ]
}

@test "hook ignores unsafe session IDs" {
  run "$REPO_ROOT/hooks/state-hook.sh" <<< '{"hook_event_name":"SessionStart","session_id":"../../escape"}'
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$CLAUDE_AGENTS_STATE_DIR")" ]
  [ ! -e "$HOME/escape.json" ]
}

@test "an event older than the stored update does not overwrite it" {
  printf '{"v":1,"sessionId":"%s","state":"waiting","updatedAt":9999999999999,"stateSince":1}\n' "$FIXTURE_SESSION" > "$(state_file)"
  run_hook SessionStart
  [ "$(state_field .state)" = waiting ]
}
