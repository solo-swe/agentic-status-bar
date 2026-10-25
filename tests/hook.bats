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

# --- Robustness -----------------------------------------------------------

@test "hook is silent and exits 0 on bad input" {
  run "$REPO_ROOT/hooks/state-hook.sh" <<< "not json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run "$REPO_ROOT/hooks/state-hook.sh" < /dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
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
