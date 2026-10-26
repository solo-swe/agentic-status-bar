#!/usr/bin/env bats

setup() {
  load test_helper
  common_setup
  stub_ps
}
teardown() { common_teardown; }

PLUGIN() { "$REPO_ROOT/swiftbar/agentic-status-bar.5s.sh" "$@"; }

# add_state ID JSON — writes a state file (compact, like the hook does), updated just now.
add_state() {
  printf '%s' "$2" | jq -c --arg id "$1" --argjson now "$(( $(date +%s) * 1000 ))" \
    '{v: 1, sessionId: $id, updatedAt: $now} + .' > "$ASB_STATE_DIR/$1.json"
}

# header_is TEXT SYMBOL — the menu-bar line shows TEXT with SF Symbol SYMBOL.
header_is() {
  [[ "${lines[0]}" == ":$2:${1:+ $1} | "* ]] || { echo "header: ${lines[0]}"; false; }
}

@test "plugin runs with no state files" {
  run PLUGIN
  [ "$status" -eq 0 ]
  header_is "" sparkle
  [[ "${lines[0]}" == *"sfcolor=#C7C7CC,#48484A"* ]]
  [ "${lines[1]}" = "---" ]
}

@test "plugin loads valid state files" {
  add_state a '{"state":"busy"}'
  add_state b '{"state":"busy"}'
  run PLUGIN
  [ "$status" -eq 0 ]
  header_is 2 sparkle
}

@test "corrupt and future-version files show the warning state" {
  add_state ok '{"state":"busy"}'
  printf 'not json' > "$ASB_STATE_DIR/corrupt.json"
  printf '{"v":2,"state":"busy"}' > "$ASB_STATE_DIR/future.json"
  printf '[1,2]' > "$ASB_STATE_DIR/array.json"
  run PLUGIN
  [ "$status" -eq 0 ]
  header_is 1 exclamationmark.triangle
  [[ "$output" == *"3 state file(s) could not be read"* ]]
}

@test "temp and lock files are ignored" {
  add_state a '{"state":"busy"}'
  printf 'partial' > "$ASB_STATE_DIR/a.json.tmp.123"
  mkdir "$ASB_STATE_DIR/a.json.lock"
  run PLUGIN
  header_is 1 sparkle
}

# --- Menu-bar item ----------------------------------------------------------

@test "waiting wins and shows the number of waiting sessions in red" {
  add_state a '{"state":"waiting","reason":"permission"}'
  add_state b '{"state":"waiting","reason":"question"}'
  add_state c '{"state":"idle"}'
  add_state d '{"state":"busy"}'
  run PLUGIN
  header_is 2 exclamationmark.circle.fill
  [[ "${lines[0]}" == *"sfcolor=#D70015,#FF453A color=#D70015,#FF453A" ]]
}

@test "idle wins over busy and shows the number of idle sessions" {
  add_state a '{"state":"idle"}'
  add_state b '{"state":"busy"}'
  add_state c '{"state":"busy"}'
  run PLUGIN
  header_is 1 zzz
  [[ "${lines[0]}" == *"sfcolor=#B25000,#FFD60A"* ]]
}

@test "all busy shows the dimmed icon with the total count" {
  add_state a '{"state":"busy"}'
  add_state b '{"state":"busy"}'
  add_state c '{"state":"busy"}'
  run PLUGIN
  header_is 3 sparkle
  [[ "${lines[0]}" == *"sfcolor=#6E6E73,#AEAEB2"* ]]
}

@test "the configured icon is used for busy and empty states" {
  printf 'icon=bolt\n' > "$ASB_CONFIG"
  add_state a '{"state":"busy"}'
  run PLUGIN
  header_is 1 bolt
}

# --- Dropdown rows --------------------------------------------------------

# now_minus SECONDS — epoch milliseconds SECONDS ago.
now_minus() { echo $(( ($(date +%s) - $1) * 1000 )); }

# rows — the session rows (lines after "---" that use the row font), without
# their leading ":symbol: ".
rows() { printf '%s\n' "${lines[@]}" | grep 'font=Menlo' | sed 's/^:[^: ]*: //'; }

@test "no sessions shows a placeholder row" {
  run PLUGIN
  [[ "$output" == *"No Claude Code sessions"* ]]
}

@test "rows are sorted by state, then longest in that state first" {
  add_state busy1 "{\"state\":\"busy\",\"cwd\":\"/x/busy-old\",\"stateSince\":$(now_minus 600)}"
  add_state idle1 "{\"state\":\"idle\",\"cwd\":\"/x/idle-new\",\"stateSince\":$(now_minus 30)}"
  add_state idle2 "{\"state\":\"idle\",\"cwd\":\"/x/idle-old\",\"stateSince\":$(now_minus 900)}"
  add_state wait1 "{\"state\":\"waiting\",\"reason\":\"permission\",\"cwd\":\"/x/waiter\",\"stateSince\":$(now_minus 5)}"
  run PLUGIN
  order="$(rows | awk '{print $1}' | tr '\n' ' ')"
  [ "$order" = "waiter idle-old idle-new busy-old " ]
}

@test "a row shows project, title, state word and duration" {
  add_state a "{\"state\":\"waiting\",\"reason\":\"permission\",\"cwd\":\"/Users/alex/code/api-gateway\",\"promptPreview\":\"Add rate limiting\",\"stateSince\":$(now_minus 125)}"
  run PLUGIN
  row="$(rows)"
  [[ "$row" == "api-gateway — Add rate limiting "* ]]
  [[ "$row" == *"  permission · 2m | font=Menlo size=12 "* ]]
}

@test "each row shows the menu-bar icon and color of its state" {
  printf 'icon=bolt\n' > "$ASB_CONFIG"
  add_state w '{"state":"waiting","reason":"permission","cwd":"/x/w"}'
  add_state i '{"state":"idle","cwd":"/x/i"}'
  add_state b '{"state":"busy","cwd":"/x/b"}'
  run PLUGIN
  all="$(printf '%s\n' "${lines[@]}" | grep 'font=Menlo')"
  [[ "$(grep '^:exclamationmark.circle.fill: w ' <<< "$all")" == *"sfcolor=#D70015,#FF453A"* ]]
  [[ "$(grep '^:zzz: i ' <<< "$all")" == *"sfcolor=#B25000,#FFD60A"* ]]
  [[ "$(grep '^:bolt: b ' <<< "$all")" == *"sfcolor=#6E6E73,#AEAEB2"* ]]
}

@test "the menu bar writes its symbol inline so SwiftBar colors it" {
  add_state a '{"state":"idle"}'
  run PLUGIN
  [ "${lines[0]}" = ":zzz: 1 | sfcolor=#B25000,#FFD60A color=#B25000,#FFD60A" ]
  [[ "$output" != *"sfimage="* ]]
}

@test "a :name: in a title doesn't become a symbol" {
  add_state a '{"state":"busy","cwd":"/x/p","promptPreview":"fix the :bug: now"}'
  run PLUGIN
  [[ "$(rows)" == *$'fix the :​bug: now'* ]]
}

@test "state words cover question, idle, working" {
  add_state q "{\"state\":\"waiting\",\"reason\":\"question\",\"cwd\":\"/x/q\"}"
  add_state i "{\"state\":\"idle\",\"cwd\":\"/x/i\"}"
  add_state b "{\"state\":\"busy\",\"cwd\":\"/x/b\"}"
  run PLUGIN
  [[ "$(rows | grep '^q ')" == *"question · "* ]]
  [[ "$(rows | grep '^i ')" == *"idle · "* ]]
  [[ "$(rows | grep '^b ')" == *"working · "* ]]
}

@test "durations use s, m, h and d" {
  add_state s "{\"state\":\"busy\",\"cwd\":\"/x/s\",\"stateSince\":$(now_minus 12)}"
  add_state m "{\"state\":\"busy\",\"cwd\":\"/x/m\",\"stateSince\":$(now_minus 300)}"
  add_state h "{\"state\":\"busy\",\"cwd\":\"/x/h\",\"stateSince\":$(now_minus 7300)}"
  add_state d "{\"state\":\"busy\",\"cwd\":\"/x/d\",\"stateSince\":$(now_minus 180000)}"
  run PLUGIN
  [[ "$(rows | grep '^s ')" =~ working\ ·\ 1[0-9]s ]]
  [[ "$(rows | grep '^m ')" == *"working · 5m |"* ]]
  [[ "$(rows | grep '^h ')" == *"working · 2h |"* ]]
  [[ "$(rows | grep '^d ')" == *"working · 2d |"* ]]
}

@test "long labels are truncated to the label width with an ellipsis" {
  add_state a '{"state":"busy","cwd":"/x/project","promptPreview":"A very long prompt preview that goes on and on past the limit"}'
  run PLUGIN
  label="$(rows | sed 's/  working.*//')"
  [ "${#label}" -eq 48 ]
  [[ "$label" == *"…" ]]
}

@test "short labels are padded so the state column lines up" {
  add_state a '{"state":"busy","cwd":"/x/ab"}'
  add_state b '{"state":"busy","cwd":"/x/abcdef","promptPreview":"x"}'
  run PLUGIN
  export LC_ALL=en_US.UTF-8
  first="$(rows | sed -n 1p)"
  second="$(rows | sed -n 2p)"
  first="${first%%working*}"
  second="${second%%working*}"
  [ "${#first}" -eq "${#second}" ]
}

@test "a pipe in the title does not break SwiftBar parameters" {
  add_state a '{"state":"busy","cwd":"/x/p","promptPreview":"a | color=red"}'
  run PLUGIN
  row="$(rows)"
  [[ "$row" == *"a │ color=red"* ]]
  [ "$(printf '%s' "$row" | tr -cd '|' | wc -c | tr -d ' ')" -eq 1 ]
}

@test "a session without cwd or title still renders" {
  add_state a '{"state":"idle"}'
  run PLUGIN
  [[ "$(rows)" == "unknown "* ]]
}

# --- Submenus and actions -------------------------------------------------

@test "each row has a submenu with session actions" {
  add_state abc123 '{"state":"busy","cwd":"/x/p","transcriptPath":"/x/t.jsonl"}'
  run PLUGIN
  plugin="$REPO_ROOT/swiftbar/agentic-status-bar.5s.sh"
  [[ "$output" == *"--Copy session ID | bash=\"$plugin\" param1=copy-id param2=abc123 terminal=false"* ]]
  [[ "$output" == *"--Copy working directory | bash=\"$plugin\" param1=copy-cwd param2=abc123 terminal=false"* ]]
  [[ "$output" == *"--Open folder in Finder | bash=\"$plugin\" param1=open-folder param2=abc123"* ]]
  [[ "$output" == *"--Reveal transcript | bash=\"$plugin\" param1=reveal-transcript param2=abc123"* ]]
}

@test "folder and transcript actions are omitted when unknown" {
  add_state abc123 '{"state":"busy"}'
  run PLUGIN
  [[ "$output" != *"Open folder"* ]]
  [[ "$output" != *"Reveal transcript"* ]]
}

@test "the menu ends with a Refresh item" {
  run PLUGIN
  [ "${lines[${#lines[@]}-1]}" = "Refresh | refresh=true" ]
}

@test "copy-id and copy-cwd put the value on the clipboard" {
  stub_command pbcopy 'cat > "$STUB_CALLS/pbcopy-input"'
  add_state abc123 '{"state":"busy","cwd":"/Users/alex/code/api-gateway"}'
  run PLUGIN copy-id abc123
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$STUB_CALLS/pbcopy-input")" = abc123 ]
  run PLUGIN copy-cwd abc123
  [ "$(cat "$STUB_CALLS/pbcopy-input")" = /Users/alex/code/api-gateway ]
}

@test "open-folder and reveal-transcript call open" {
  stub_command open
  mkdir -p "$TEST_TMP/proj"
  : > "$TEST_TMP/t.jsonl"
  add_state abc123 "{\"state\":\"busy\",\"cwd\":\"$TEST_TMP/proj\",\"transcriptPath\":\"$TEST_TMP/t.jsonl\"}"
  run PLUGIN open-folder abc123
  run PLUGIN reveal-transcript abc123
  [ "$(stub_calls open)" = "$(printf '%s\n-R %s' "$TEST_TMP/proj" "$TEST_TMP/t.jsonl")" ]
}

@test "actions ignore unsafe or unknown session IDs" {
  stub_command open
  stub_command pbcopy
  run PLUGIN open-folder ../../etc
  [ "$status" -eq 0 ]
  run PLUGIN copy-id missing
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls open)" ]
}

# --- C1 liveness ----------------------------------------------------------

@test "C1 keeps a session whose claude process is running" {
  add_process 4242 1 claude claude "Mon Oct 19 09:12:03 2026"
  add_state a '{"state":"busy","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026"}'
  run PLUGIN
  header_is 1 sparkle
  [ -e "$ASB_STATE_DIR/a.json" ]
}

@test "C1 drops and deletes a session whose process is gone" {
  add_process 4242 1 claude claude "Mon Oct 19 09:12:03 2026"
  add_state alive '{"state":"busy","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026"}'
  add_state gone '{"state":"waiting","pid":5555,"procStart":"Mon Oct 19 09:00:00 2026"}'
  run PLUGIN
  header_is 1 sparkle
  [ -e "$ASB_STATE_DIR/alive.json" ]
  [ ! -e "$ASB_STATE_DIR/gone.json" ]
}

@test "C1 treats a reused PID with a different start time as dead" {
  add_process 4242 1 zsh zsh "Tue Oct 20 10:00:00 2026"
  add_state reused '{"state":"busy","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026"}'
  run PLUGIN
  header_is "" sparkle
  [ ! -e "$ASB_STATE_DIR/reused.json" ]
}

@test "C1 ignores extra spaces in start times" {
  add_process 4242 1 claude claude "Mon Oct  5 09:12:03 2026"
  add_state a '{"state":"busy","pid":4242,"procStart":"Mon Oct 5 09:12:03 2026"}'
  run PLUGIN
  header_is 1 sparkle
}

@test "C1 keeps sessions without a recorded pid" {
  add_state nopid '{"state":"busy"}'
  run PLUGIN
  header_is 1 sparkle
  [ -e "$ASB_STATE_DIR/nopid.json" ]
}

@test "a missing asb shows a build hint and actions do nothing" {
  # A copy of the plugin outside the repo has no .build to fall back to.
  mkdir -p "$TEST_TMP/elsewhere/swiftbar"
  cp "$REPO_ROOT/swiftbar/agentic-status-bar.5s.sh" "$TEST_TMP/elsewhere/swiftbar/"
  ASB_BIN=/nonexistent/asb run "$TEST_TMP/elsewhere/swiftbar/agentic-status-bar.5s.sh"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == ":exclamationmark.triangle: | sfcolor=#B25000,#FFD60A" ]]
  [[ "$output" == *"swift build -c release"* ]]
  ASB_BIN=/nonexistent/asb run "$TEST_TMP/elsewhere/swiftbar/agentic-status-bar.5s.sh" copy-id abc
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "plugin works through a symlink" {
  ln -s "$REPO_ROOT/swiftbar/agentic-status-bar.5s.sh" "$TEST_TMP/linked.5s.sh"
  add_state a '{"state":"busy"}'
  run "$TEST_TMP/linked.5s.sh"
  [ "$status" -eq 0 ]
  header_is 1 sparkle
}
