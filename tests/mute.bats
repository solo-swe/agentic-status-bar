#!/usr/bin/env bats
# Muting a project from its row.

setup() {
  load test_helper
  common_setup
  stub_ps
}
teardown() { common_teardown; }

PLUGIN() { "$REPO_ROOT/swiftbar/swiftbar-claudecode-minimal.5s.sh" "$@"; }

now_ms() { echo $(( $(date +%s) * 1000 )); }

# add_state ID JSON — a state file updated just now.
add_state() {
  printf '%s' "$2" | jq -c --arg id "$1" --argjson now "$(now_ms)" \
    '{v: 1, sessionId: $id, updatedAt: $now} + .' > "$CLAUDE_STATUSBAR_STATE_DIR/$1.json"
}

mutes() { cat "$CLAUDE_STATUSBAR_STATE_DIR/mutes"; }
row_of() { printf '%s\n' "${lines[@]}" | grep 'font=Menlo' | grep "^:[^: ]*: $1 "; }
header_is() {
  [[ "${lines[0]}" == ":$2:${1:+ $1} | "* ]] || { echo "header: ${lines[0]}"; false; }
}

@test "rows offer muting their project for an hour or for today" {
  add_state a '{"state":"idle","cwd":"/x/alpha"}'
  run PLUGIN
  plugin="$REPO_ROOT/swiftbar/swiftbar-claudecode-minimal.5s.sh"
  [[ "$output" == *"--Mute project for 1 hour | bash=\"$plugin\" param1=mute-hour param2=a terminal=false refresh=true"* ]]
  [[ "$output" == *"--Mute project for today | bash=\"$plugin\" param1=mute-today param2=a terminal=false refresh=true"* ]]
  [[ "$output" != *"Unmute"* ]]
}

@test "a row without a cwd has no mute items" {
  add_state a '{"state":"idle"}'
  run PLUGIN
  [[ "$output" != *"Mute project"* ]]
}

@test "mute-hour mutes the project for 60 minutes" {
  add_state a '{"state":"idle","cwd":"/x/alpha"}'
  before=$(now_ms)
  run PLUGIN mute-hour a
  [ "$status" -eq 0 ]
  until=$(mutes | jq '.["/x/alpha"].until')
  [ "$until" -ge $(( before + 3600000 )) ]
  [ "$until" -le $(( before + 3602000 )) ]
  [ "$(mutes | jq '.["/x/alpha"].today')" = false ]
}

@test "mute-today mutes the project until local midnight" {
  add_state a '{"state":"idle","cwd":"/x/alpha"}'
  run PLUGIN mute-today a
  until=$(mutes | jq '.["/x/alpha"].until')
  [ "$(date -r $(( until / 1000 )) '+%H:%M:%S')" = "00:00:00" ]
  [ "$until" -gt "$(now_ms)" ]
  [ "$until" -le $(( $(now_ms) + 86400000 + 3600000 )) ]
}

@test "a muted idle session is out of the count and shows the muted icon" {
  add_state a '{"state":"idle","cwd":"/x/alpha"}'
  add_state b '{"state":"idle","cwd":"/x/beta"}'
  run PLUGIN mute-hour a
  run PLUGIN
  header_is 1 zzz
  [[ "$(row_of alpha)" == ":bell.slash: alpha "*"idle · muted until "[0-2][0-9]:[0-5][0-9]" | "*"sfcolor=#8E8E93,#98989D"* ]]
  # Muted rows come last.
  [[ "$(printf '%s\n' "${lines[@]}" | grep 'font=Menlo' | tail -1)" == ":bell.slash: alpha "* ]]
}

@test "a project muted for today says so" {
  add_state a '{"state":"idle","cwd":"/x/alpha"}'
  run PLUGIN mute-today a
  run PLUGIN
  [[ "$(row_of alpha)" == *"idle · muted today | "* ]]
}

@test "every session in the muted project is muted" {
  add_state a '{"state":"idle","cwd":"/x/alpha"}'
  run PLUGIN mute-hour a
  add_state a2 '{"state":"busy","cwd":"/x/alpha"}'
  run PLUGIN
  [[ "$(row_of alpha | grep -c '^:bell.slash:')" -eq 2 ]]
}

@test "when every session is muted the menu bar shows the muted icon without a number" {
  add_state a '{"state":"idle","cwd":"/x/alpha"}'
  add_state b '{"state":"busy","cwd":"/x/alpha"}'
  run PLUGIN mute-today a
  run PLUGIN
  header_is "" bell.slash
}

@test "a muted session waiting on the user still turns the menu bar red" {
  add_state a '{"state":"waiting","reason":"permission","cwd":"/x/alpha"}'
  run PLUGIN mute-hour a
  run PLUGIN
  header_is 1 exclamationmark.circle.fill
  [[ "$(row_of alpha)" == ":exclamationmark.circle.fill: "* ]]
  [[ "$output" == *"--Unmute project"* ]]
}

@test "unmute lifts the mute and the row offers muting again" {
  add_state a '{"state":"idle","cwd":"/x/alpha"}'
  run PLUGIN mute-hour a
  run PLUGIN unmute a
  [ "$(mutes)" = "{}" ]
  run PLUGIN
  header_is 1 zzz
  [[ "$output" == *"--Mute project for 1 hour"* ]]
}

@test "Unmute all appears only while something is muted and clears every mute" {
  add_state a '{"state":"idle","cwd":"/x/alpha"}'
  add_state b '{"state":"idle","cwd":"/x/beta"}'
  run PLUGIN
  [[ "$output" != *"Unmute all"* ]]
  run PLUGIN mute-hour a
  run PLUGIN mute-today b
  run PLUGIN
  [[ "$output" == *"Unmute all projects | bash="*"param1=unmute-all terminal=false refresh=true"* ]]
  run PLUGIN unmute-all
  [ "$(mutes)" = "{}" ]
}

@test "a prompt sent after the mute lifts it" {
  add_state a '{"state":"idle","cwd":"/x/alpha"}'
  run PLUGIN mute-hour a
  add_state a "{\"state\":\"idle\",\"cwd\":\"/x/alpha\",\"promptAt\":$(( $(now_ms) + 1000 ))}"
  run PLUGIN
  header_is 1 zzz
  [[ "$(row_of alpha)" == ":zzz: "* ]]
}

@test "a prompt sent before the mute doesn't lift it" {
  add_state a "{\"state\":\"idle\",\"cwd\":\"/x/alpha\",\"promptAt\":$(( $(now_ms) - 60000 ))}"
  run PLUGIN mute-hour a
  run PLUGIN
  header_is "" bell.slash
}

@test "expired mutes are ignored and dropped on the next change" {
  add_state a '{"state":"idle","cwd":"/x/alpha"}'
  add_state b '{"state":"idle","cwd":"/x/beta"}'
  printf '{"/x/alpha":{"until":1000,"at":500,"today":false}}' > "$CLAUDE_STATUSBAR_STATE_DIR/mutes"
  run PLUGIN
  header_is 2 zzz
  run PLUGIN mute-hour b
  [ "$(mutes | jq -c 'keys')" = '["/x/beta"]' ]
}

@test "a corrupt mutes file is ignored and replaced on the next change" {
  add_state a '{"state":"idle","cwd":"/x/alpha"}'
  printf 'garbage' > "$CLAUDE_STATUSBAR_STATE_DIR/mutes"
  run PLUGIN
  [ "$status" -eq 0 ]
  header_is 1 zzz
  run PLUGIN mute-hour a
  [ "$(mutes | jq -c 'keys')" = '["/x/alpha"]' ]
}

@test "mute actions ignore unsafe or unknown session IDs" {
  run PLUGIN mute-hour '../etc'
  [ "$status" -eq 0 ]
  run PLUGIN mute-today nosuch
  [ "$status" -eq 0 ]
  [ ! -s "$CLAUDE_STATUSBAR_STATE_DIR/mutes" ] || [ "$(mutes)" = "{}" ]
}
