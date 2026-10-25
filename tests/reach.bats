#!/usr/bin/env bats
# Focus, titles, subagents, filters and settings.

setup() {
  load test_helper
  common_setup
  stub_ps
  stub_command open
  stub_command herdr
  export CLAUDE_AGENTS_HERDR="$FAKE_BIN/herdr"
}
teardown() { common_teardown; }

PLUGIN() { "$REPO_ROOT/swiftbar/claude-agents.5s.sh" "$@"; }

add_state() {
  printf '%s' "$2" | jq -c --arg id "$1" --argjson now "$(( $(date +%s) * 1000 ))" \
    '{v: 1, sessionId: $id, updatedAt: $now, cwd: "/x/\($id)"} + .' > "$CLAUDE_AGENTS_STATE_DIR/$1.json"
}

row_of() { printf '%s\n' "${lines[@]}" | grep 'font=Menlo' | grep " $1 "; }

# --- Focus ----------------------------------------------------------------

@test "a row in a herdr pane focuses it on click" {
  add_state s1 '{"state":"idle","herdrPane":"w2:p1"}'
  run PLUGIN
  [[ "$(row_of s1)" == *"font=Menlo size=12 bash=\"$REPO_ROOT/swiftbar/claude-agents.5s.sh\" param1=focus param2=s1 terminal=false" ]]
  [[ "$output" != *"Not in herdr"* ]]
}

@test "a row outside herdr has no click action and says why" {
  add_state s1 '{"state":"idle"}'
  run PLUGIN
  [[ "$(row_of s1)" == *"font=Menlo size=12" ]]
  [[ "$output" == *"--Not in herdr: click to focus is unavailable | color=gray"* ]]
}

@test "rows have no click action when herdr is not installed" {
  export CLAUDE_AGENTS_HERDR=/nonexistent/herdr
  add_state s1 '{"state":"idle","herdrPane":"w2:p1"}'
  run PLUGIN
  [[ "$(row_of s1)" == *"font=Menlo size=12" ]]
  [[ "$output" == *"Not in herdr"* ]]
}

@test "focus calls herdr, then raises the terminal" {
  add_state s1 '{"state":"idle","herdrPane":"w2:p1","termBundleId":"com.example.terminal"}'
  run PLUGIN focus s1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(stub_calls herdr)" = "agent focus w2:p1" ]
  [ "$(stub_calls open)" = "-b com.example.terminal" ]
}

@test "focus does nothing else when herdr fails" {
  stub_command herdr 'exit 1'
  add_state s1 '{"state":"idle","herdrPane":"w2:p1","termBundleId":"com.example.terminal"}'
  run PLUGIN focus s1
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls open)" ]
}

@test "focus gives up on a hanging herdr" {
  stub_command herdr 'sleep 10'
  add_state s1 '{"state":"idle","herdrPane":"w2:p1","termBundleId":"com.example.terminal"}'
  start=$(date +%s)
  run PLUGIN focus s1
  [ "$status" -eq 0 ]
  [ $(( $(date +%s) - start )) -lt 5 ]
  [ -z "$(stub_calls open)" ]
}

@test "focus skips raising the terminal when no bundle ID is known" {
  add_state s1 '{"state":"idle","herdrPane":"w2:p1"}'
  run PLUGIN focus s1
  [ "$(stub_calls herdr)" = "agent focus w2:p1" ]
  [ -z "$(stub_calls open)" ]
}

@test "focus ignores unsafe pane and bundle values" {
  add_state s1 '{"state":"idle","herdrPane":"w2:p1; rm -rf /"}'
  run PLUGIN focus s1
  [ -z "$(stub_calls herdr)" ]
  add_state s2 '{"state":"idle","herdrPane":"w2:p1","termBundleId":"com.x; evil"}'
  run PLUGIN focus s2
  [ -z "$(stub_calls open)" ]
}
