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

# --- Titles ---------------------------------------------------------------

# herdr_lists JSON_AGENTS — makes the herdr stub answer `agent list` with these agents.
herdr_lists() {
  printf '{"id":"cli:agent:list","result":{"agents":%s,"type":"agent_list"}}' "$1" > "$TEST_TMP/herdr-list.json"
  stub_command herdr '[ "$1 $2" = "agent list" ] && cat "'"$TEST_TMP"'/herdr-list.json"; exit 0'
}

@test "herdr terminal titles are preferred over the prompt preview" {
  herdr_lists '[{"agent":"claude","agent_session":{"value":"s1"},"terminal_title_stripped":"Spec for the parser","pane_id":"w2:p1"}]'
  add_state s1 '{"state":"idle","promptPreview":"first prompt"}'
  run PLUGIN
  [[ "$(row_of s1)" == "● s1 — Spec for the parser "* ]]
}

@test "a user-given session name is used when herdr has no title" {
  herdr_lists '[]'
  add_process 4242 1 claude claude "Mon Oct 19 09:12:03 2026"
  add_state s1 '{"state":"idle","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026","promptPreview":"first prompt"}'
  printf '{"pid":4242,"sessionId":"s1","name":"parser-rewrite","nameSource":"user"}' > "$CLAUDE_AGENTS_REGISTRY_DIR/4242.json"
  run PLUGIN
  [[ "$(row_of s1)" == "● s1 — parser-rewrite "* ]]
}

@test "derived session names are skipped in favor of the prompt preview" {
  herdr_lists '[]'
  add_process 4242 1 claude claude "Mon Oct 19 09:12:03 2026"
  add_state s1 '{"state":"idle","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026","promptPreview":"first prompt"}'
  printf '{"pid":4242,"sessionId":"s1","name":"s1-a3","nameSource":"derived"}' > "$CLAUDE_AGENTS_REGISTRY_DIR/4242.json"
  run PLUGIN
  [[ "$(row_of s1)" == "● s1 — first prompt "* ]]
}

@test "a failing or slow herdr list falls back to the prompt preview" {
  stub_command herdr 'exit 1'
  add_state s1 '{"state":"idle","promptPreview":"first prompt"}'
  run PLUGIN
  [[ "$(row_of s1)" == "● s1 — first prompt "* ]]

  stub_command herdr 'sleep 10'
  start=$(date +%s)
  run PLUGIN
  [ $(( $(date +%s) - start )) -lt 4 ]
  [[ "$(row_of s1)" == "● s1 — first prompt "* ]]
}

@test "an empty herdr title falls back too" {
  herdr_lists '[{"agent":"claude","agent_session":{"value":"s1"},"terminal_title_stripped":""}]'
  add_state s1 '{"state":"idle","promptPreview":"first prompt"}'
  run PLUGIN
  [[ "$(row_of s1)" == "● s1 — first prompt "* ]]
}

# --- Subagents ------------------------------------------------------------

sub_rows() { printf '%s\n' "${lines[@]}" | grep '↳ subagent'; }

@test "subagents are listed under their parent" {
  now=$(( $(date +%s) * 1000 ))
  add_state s1 "{\"state\":\"busy\",\"subagents\":{\"a1\":{\"type\":\"Explore\",\"since\":$(( now - 12000 ))},\"a2\":{\"type\":\"general-purpose\",\"since\":$(( now - 60000 ))}}}"
  add_state s2 '{"state":"idle"}'
  run PLUGIN
  [ "$(sub_rows | wc -l | tr -d ' ')" -eq 2 ]
  [[ "$(sub_rows | sed -n 1p)" == "  ↳ subagent: general-purpose "*"  working · 1m | font=Menlo size=12 color=gray" ]]
  [[ "$(sub_rows | sed -n 2p)" == "  ↳ subagent: Explore "*"  working · 1"[0-9]"s | font=Menlo size=12 color=gray" ]]
  # They come after the parent row, not after the other session.
  parent_line=$(printf '%s\n' "${lines[@]}" | grep -n ' s1 ' | head -1 | cut -d: -f1)
  sub_line=$(printf '%s\n' "${lines[@]}" | grep -n '↳ subagent' | head -1 | cut -d: -f1)
  other_line=$(printf '%s\n' "${lines[@]}" | grep -n ' s2 ' | head -1 | cut -d: -f1)
  [ "$sub_line" -gt "$parent_line" ]
  [ "$other_line" -lt "$parent_line" ]
}

@test "subagents don't count toward the menu-bar state" {
  add_state s1 '{"state":"idle","subagents":{"a1":{"type":"Explore","since":1}}}'
  run PLUGIN
  [[ "${lines[0]}" == "1 | sfimage=checkmark.circle "* ]]
}

@test "subagent rows are hidden when show_subagents=0" {
  printf 'show_subagents=0\n' > "$CLAUDE_AGENTS_CONFIG"
  add_state s1 '{"state":"busy","subagents":{"a1":{"type":"Explore","since":1}}}'
  run PLUGIN
  [ -z "$(sub_rows)" ]
}

@test "focus ignores unsafe pane and bundle values" {
  add_state s1 '{"state":"idle","herdrPane":"w2:p1; rm -rf /"}'
  run PLUGIN focus s1
  [ -z "$(stub_calls herdr)" ]
  add_state s2 '{"state":"idle","herdrPane":"w2:p1","termBundleId":"com.x; evil"}'
  run PLUGIN focus s2
  [ -z "$(stub_calls open)" ]
}
