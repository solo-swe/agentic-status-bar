#!/usr/bin/env bats

setup() {
  load test_helper
  common_setup
  stub_ps
}
teardown() { common_teardown; }

PLUGIN() { "$REPO_ROOT/swiftbar/claude-agents.5s.sh" "$@"; }

# add_state ID JSON — writes a state file (compact, like the hook does).
add_state() {
  printf '%s' "$2" | jq -c --arg id "$1" '{v: 1, sessionId: $id} + .' > "$CLAUDE_AGENTS_STATE_DIR/$1.json"
}

@test "plugin runs with no state files" {
  run PLUGIN
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "✳ 0" ]
  [ "${lines[1]}" = "---" ]
}

@test "plugin loads valid state files" {
  add_state a '{"state":"busy"}'
  add_state b '{"state":"idle"}'
  run PLUGIN
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "✳ 2" ]
}

@test "corrupt and future-version files show the warning state" {
  add_state ok '{"state":"busy"}'
  printf 'not json' > "$CLAUDE_AGENTS_STATE_DIR/corrupt.json"
  printf '{"v":2,"state":"busy"}' > "$CLAUDE_AGENTS_STATE_DIR/future.json"
  printf '[1,2]' > "$CLAUDE_AGENTS_STATE_DIR/array.json"
  run PLUGIN
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "⚠︎ 1 | sfimage=exclamationmark.triangle" ]]
  [[ "$output" == *"3 state file(s) could not be read"* ]]
}

@test "temp and lock files are ignored" {
  add_state a '{"state":"busy"}'
  printf 'partial' > "$CLAUDE_AGENTS_STATE_DIR/a.json.tmp.123"
  mkdir "$CLAUDE_AGENTS_STATE_DIR/a.json.lock"
  run PLUGIN
  [ "${lines[0]}" = "✳ 1" ]
}

# --- C1 liveness ----------------------------------------------------------

@test "C1 keeps a session whose claude process is running" {
  add_process 4242 1 claude claude "Mon Oct 19 09:12:03 2026"
  add_state a '{"state":"busy","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026"}'
  run PLUGIN
  [ "${lines[0]}" = "✳ 1" ]
  [ -e "$CLAUDE_AGENTS_STATE_DIR/a.json" ]
}

@test "C1 drops and deletes a session whose process is gone" {
  add_process 4242 1 claude claude "Mon Oct 19 09:12:03 2026"
  add_state alive '{"state":"busy","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026"}'
  add_state gone '{"state":"waiting","pid":5555,"procStart":"Mon Oct 19 09:00:00 2026"}'
  run PLUGIN
  [ "${lines[0]}" = "✳ 1" ]
  [ -e "$CLAUDE_AGENTS_STATE_DIR/alive.json" ]
  [ ! -e "$CLAUDE_AGENTS_STATE_DIR/gone.json" ]
}

@test "C1 treats a reused PID with a different start time as dead" {
  add_process 4242 1 zsh zsh "Tue Oct 20 10:00:00 2026"
  add_state reused '{"state":"busy","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026"}'
  run PLUGIN
  [ "${lines[0]}" = "✳ 0" ]
  [ ! -e "$CLAUDE_AGENTS_STATE_DIR/reused.json" ]
}

@test "C1 ignores extra spaces in start times" {
  add_process 4242 1 claude claude "Mon Oct  5 09:12:03 2026"
  add_state a '{"state":"busy","pid":4242,"procStart":"Mon Oct 5 09:12:03 2026"}'
  run PLUGIN
  [ "${lines[0]}" = "✳ 1" ]
}

@test "C1 keeps sessions without a recorded pid" {
  add_state nopid '{"state":"busy"}'
  run PLUGIN
  [ "${lines[0]}" = "✳ 1" ]
  [ -e "$CLAUDE_AGENTS_STATE_DIR/nopid.json" ]
}

@test "missing jq shows an install hint" {
  CLAUDE_AGENTS_JQ=/nonexistent/jq run PLUGIN
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "⚠︎ | sfimage=exclamationmark.triangle" ]]
  [[ "$output" == *"brew install jq"* ]]
}

@test "plugin works through a symlink" {
  ln -s "$REPO_ROOT/swiftbar/claude-agents.5s.sh" "$TEST_TMP/linked.5s.sh"
  add_state a '{"state":"busy"}'
  run "$TEST_TMP/linked.5s.sh"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "✳ 1" ]
}
