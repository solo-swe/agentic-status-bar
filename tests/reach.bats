#!/usr/bin/env bats
# Focus, titles, subagents, filters and settings.

setup() {
  load test_helper
  common_setup
  stub_ps
  stub_command open
  stub_command herdr
  export CLAUDE_STATUSBAR_HERDR="$FAKE_BIN/herdr"
}
teardown() { common_teardown; }

PLUGIN() { "$REPO_ROOT/swiftbar/swiftbar-claudecode-minimal.5s.sh" "$@"; }

add_state() {
  printf '%s' "$2" | jq -c --arg id "$1" --argjson now "$(( $(date +%s) * 1000 ))" \
    '{v: 1, sessionId: $id, updatedAt: $now, cwd: "/x/\($id)"} + .' > "$CLAUDE_STATUSBAR_STATE_DIR/$1.json"
}

row_of() { printf '%s\n' "${lines[@]}" | grep 'font=Menlo' | grep " $1 "; }

# --- Focus ----------------------------------------------------------------

@test "a row in a herdr pane focuses it on click" {
  add_state s1 '{"state":"idle","herdrPane":"w2:p1"}'
  run PLUGIN
  [[ "$(row_of s1)" == *"font=Menlo size=12 bash=\"$REPO_ROOT/swiftbar/swiftbar-claudecode-minimal.5s.sh\" param1=focus param2=s1 terminal=false" ]]
  [[ "$output" != *"Not in herdr"* ]]
}

@test "a row outside herdr has no click action and says why" {
  add_state s1 '{"state":"idle"}'
  run PLUGIN
  [[ "$(row_of s1)" == *"font=Menlo size=12" ]]
  [[ "$output" == *"--Not in herdr: click to focus is unavailable | color=gray"* ]]
}

@test "rows have no click action when herdr is not installed" {
  export CLAUDE_STATUSBAR_HERDR=/nonexistent/herdr
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
  printf '{"pid":4242,"sessionId":"s1","name":"parser-rewrite","nameSource":"user"}' > "$CLAUDE_STATUSBAR_REGISTRY_DIR/4242.json"
  run PLUGIN
  [[ "$(row_of s1)" == "● s1 — parser-rewrite "* ]]
}

@test "derived session names are skipped in favor of the prompt preview" {
  herdr_lists '[]'
  add_process 4242 1 claude claude "Mon Oct 19 09:12:03 2026"
  add_state s1 '{"state":"idle","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026","promptPreview":"first prompt"}'
  printf '{"pid":4242,"sessionId":"s1","name":"s1-a3","nameSource":"derived"}' > "$CLAUDE_STATUSBAR_REGISTRY_DIR/4242.json"
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
  printf 'show_subagents=0\n' > "$CLAUDE_STATUSBAR_CONFIG"
  add_state s1 '{"state":"busy","subagents":{"a1":{"type":"Explore","since":1}}}'
  run PLUGIN
  [ -z "$(sub_rows)" ]
}

# --- Filters --------------------------------------------------------------

@test "the Show section lists every filter, checked by default" {
  run PLUGIN
  plugin="$REPO_ROOT/swiftbar/swiftbar-claudecode-minimal.5s.sh"
  [[ "$output" == *"Interactive | bash=\"$plugin\" param1=toggle param2=show_interactive terminal=false refresh=true checked=true"* ]]
  [[ "$output" == *"Headless (claude -p) | bash=\"$plugin\" param1=toggle param2=show_headless terminal=false refresh=true checked=true"* ]]
  [[ "$output" == *"param2=show_subagents terminal=false refresh=true checked=true"* ]]
  [[ "$output" == *"param2=show_ide terminal=false refresh=true checked=true"* ]]
}

@test "toggle flips a filter in the config file" {
  run PLUGIN toggle show_headless
  [ "$status" -eq 0 ]
  grep -q '^show_headless=0$' "$CLAUDE_STATUSBAR_CONFIG"
  run PLUGIN toggle show_headless
  grep -q '^show_headless=1$' "$CLAUDE_STATUSBAR_CONFIG"
}

@test "toggle ignores unknown keys" {
  run PLUGIN toggle stale_minutes
  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_STATUSBAR_CONFIG" ]
}

@test "an unchecked filter is shown without a checkmark" {
  printf 'show_ide=0\n' > "$CLAUDE_STATUSBAR_CONFIG"
  run PLUGIN
  [[ "$output" == *"param2=show_ide terminal=false refresh=true"$'\n'* || "$output" == *"param2=show_ide terminal=false refresh=true" ]]
  [[ "$output" != *"param2=show_ide terminal=false refresh=true checked=true"* ]]
}

@test "hidden kinds are left out of rows and the menu-bar count" {
  printf 'show_headless=0\nshow_ide=0\n' > "$CLAUDE_STATUSBAR_CONFIG"
  add_state cli '{"state":"busy","kind":"interactive"}'
  add_state script '{"state":"waiting","reason":"permission","kind":"headless"}'
  add_state vscode '{"state":"idle","kind":"ide"}'
  add_state app '{"state":"idle","kind":"desktop"}'
  run PLUGIN
  [[ "${lines[0]}" == "1 | sfimage=sparkle "* ]]
  [ -n "$(row_of cli)" ]
  [ -z "$(row_of script)" ]
  [ -z "$(row_of vscode)" ]
  [ -z "$(row_of app)" ]
}

@test "sessions without a kind count as interactive" {
  printf 'show_interactive=0\n' > "$CLAUDE_STATUSBAR_CONFIG"
  add_state old '{"state":"busy"}'
  run PLUGIN
  [ -z "$(row_of old)" ]
}

# --- Settings -------------------------------------------------------------

@test "the Settings submenu shows the current values" {
  run PLUGIN
  [[ "$output" == *$'\nSettings…\n'* ]]
  [[ "$output" == *"----30 minutes | bash=\""*"param1=set param2=stale_minutes param3=30 terminal=false refresh=true checked=true"* ]]
  [[ "$output" == *"----10 minutes | bash=\""*"param3=10 terminal=false refresh=true"$'\n'* ]]
  [[ "$output" == *"----Never | bash=\""*"param3=0 terminal=false refresh=true"$'\n'* ]]
  [[ "$output" == *"--Refresh instantly on changes | bash=\""*"param2=instant_refresh terminal=false refresh=true checked=true"* ]]
  [[ "$output" == *"--Use Claude Code session registry | bash=\""*"param2=use_registry terminal=false refresh=true checked=true"* ]]
  [[ "$output" == *"--Store prompt previews | bash=\""*"param2=store_prompt_preview terminal=false refresh=true checked=true"* ]]
  [[ "$output" == *"--Reveal config file | bash=\""*"param1=reveal-config terminal=false refresh=true"* ]]
}

@test "set changes the stale threshold to an offered value" {
  run PLUGIN set stale_minutes 60
  grep -q '^stale_minutes=60$' "$CLAUDE_STATUSBAR_CONFIG"
  run PLUGIN
  [[ "$output" == *"param3=60 terminal=false refresh=true checked=true"* ]]
}

@test "set rejects other keys and values" {
  run PLUGIN set stale_minutes 7
  run PLUGIN set icon bolt
  run PLUGIN set stale_minutes '1;touch x'
  [ ! -e "$CLAUDE_STATUSBAR_CONFIG" ]
}

@test "settings toggles flip their keys" {
  run PLUGIN toggle instant_refresh
  run PLUGIN toggle use_registry
  run PLUGIN toggle store_prompt_preview
  grep -q '^instant_refresh=0$' "$CLAUDE_STATUSBAR_CONFIG"
  grep -q '^use_registry=0$' "$CLAUDE_STATUSBAR_CONFIG"
  grep -q '^store_prompt_preview=0$' "$CLAUDE_STATUSBAR_CONFIG"
  run PLUGIN
  [[ "$output" == *"param2=use_registry terminal=false refresh=true"$'\n'* ]]
}

@test "reveal-config creates the config with defaults and reveals it" {
  run PLUGIN reveal-config
  [ "$status" -eq 0 ]
  grep -q '^stale_minutes=30$' "$CLAUDE_STATUSBAR_CONFIG"
  grep -q '^icon=sparkle$' "$CLAUDE_STATUSBAR_CONFIG"
  [ "$(stub_calls open)" = "-R $CLAUDE_STATUSBAR_CONFIG" ]
}

@test "reveal-config keeps an existing config" {
  printf 'icon=bolt\n' > "$CLAUDE_STATUSBAR_CONFIG"
  run PLUGIN reveal-config
  [ "$(cat "$CLAUDE_STATUSBAR_CONFIG")" = "icon=bolt" ]
}

@test "focus ignores unsafe pane and bundle values" {
  add_state s1 '{"state":"idle","herdrPane":"w2:p1; rm -rf /"}'
  run PLUGIN focus s1
  [ -z "$(stub_calls herdr)" ]
  add_state s2 '{"state":"idle","herdrPane":"w2:p1","termBundleId":"com.x; evil"}'
  run PLUGIN focus s2
  [ -z "$(stub_calls open)" ]
}
