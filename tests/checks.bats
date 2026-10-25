#!/usr/bin/env bats
# Reconciliation checks C2-C5 (C1 is in plugin.bats).

setup() {
  load test_helper
  common_setup
  stub_ps
  add_process 4242 1 claude claude "Mon Oct 19 09:12:03 2026"
}
teardown() { common_teardown; }

PLUGIN() { "$REPO_ROOT/swiftbar/claude-agents.5s.sh" "$@"; }

# add_session JSON — the state file of a live session (pid 4242) merged with JSON.
add_session() {
  printf '%s' "$1" | jq -c '{v: 1, sessionId: "s1", pid: 4242, procStart: "Mon Oct 19 09:12:03 2026", cwd: "/x/proj", updatedAt: 1000, stateSince: 1000} + .' \
    > "$CLAUDE_AGENTS_STATE_DIR/s1.json"
}

# add_registry JSON — Claude Code's registry entry for pid 4242 merged with JSON.
add_registry() {
  printf '%s' "$1" | jq -c '{pid: 4242, sessionId: "s1"} + .' > "$CLAUDE_AGENTS_REGISTRY_DIR/4242.json"
}

header_is() {
  [[ "${lines[0]}" == "$1 | sfimage=$2 "* ]] || { echo "header: ${lines[0]}"; false; }
}

# --- C2 registry override -------------------------------------------------

@test "C2 uses a newer registry status" {
  add_session '{"state":"busy","updatedAt":1000}'
  add_registry '{"status":"idle","statusUpdatedAt":2000}'
  run PLUGIN
  header_is 1 checkmark.circle
}

@test "C2 maps a newer registry waiting status with its reason" {
  add_session '{"state":"busy","updatedAt":1000}'
  add_registry '{"status":"waiting","waitingFor":"permission prompt","statusUpdatedAt":2000}'
  run PLUGIN
  header_is 1 exclamationmark.circle.fill
  [[ "$output" == *"permission · "* ]]
}

@test "C2 ignores an older registry status" {
  add_session '{"state":"waiting","reason":"permission","updatedAt":3000}'
  add_registry '{"status":"busy","statusUpdatedAt":2000}'
  run PLUGIN
  header_is 1 exclamationmark.circle.fill
}

@test "C2 ignores a registry entry for another session" {
  add_session '{"state":"busy","updatedAt":1000}'
  add_registry '{"sessionId":"someone-else","status":"idle","statusUpdatedAt":2000}'
  run PLUGIN
  header_is 1 sparkle
}

@test "C2 ignores an unknown registry status" {
  add_session '{"state":"busy","updatedAt":1000}'
  add_registry '{"status":"thinking-hard","statusUpdatedAt":2000}'
  run PLUGIN
  header_is 1 sparkle
}

@test "C2 logs once and ignores a registry entry without status" {
  add_session '{"state":"busy","updatedAt":1000}'
  add_registry '{"statusUpdatedAt":2000}'
  run PLUGIN
  header_is 1 sparkle
  run PLUGIN
  [ "$(grep -c '^\[registry-schema\]' "$CLAUDE_AGENTS_STATE_DIR/plugin.log")" -eq 1 ]
}

@test "C2 is off when use_registry=0" {
  printf 'use_registry=0\n' > "$CLAUDE_AGENTS_CONFIG"
  add_session '{"state":"busy","updatedAt":1000}'
  add_registry '{"status":"idle","statusUpdatedAt":2000}'
  run PLUGIN
  header_is 1 sparkle
}

@test "C2 never modifies the state file" {
  add_session '{"state":"busy","updatedAt":1000}'
  add_registry '{"status":"idle","statusUpdatedAt":2000}'
  before="$(cat "$CLAUDE_AGENTS_STATE_DIR/s1.json")"
  run PLUGIN
  [ "$(cat "$CLAUDE_AGENTS_STATE_DIR/s1.json")" = "$before" ]
}

# --- C3 interrupt ---------------------------------------------------------

# use_transcript NAME — copies tests/fixtures/transcripts/NAME.jsonl into place
# and prints its path.
use_transcript() {
  cp "$REPO_ROOT/tests/fixtures/transcripts/$1.jsonl" "$TEST_TMP/transcript.jsonl"
  printf '%s\n' "$TEST_TMP/transcript.jsonl"
}

@test "C3 shows a busy session as idle after a denied permission" {
  t="$(use_transcript denied-permission)"
  add_session "{\"state\":\"busy\",\"transcriptPath\":\"$t\"}"
  run PLUGIN
  header_is 1 checkmark.circle
}

@test "C3 shows a waiting session as idle after a denied permission" {
  t="$(use_transcript denied-permission)"
  add_session "{\"state\":\"waiting\",\"reason\":\"permission\",\"transcriptPath\":\"$t\"}"
  run PLUGIN
  header_is 1 checkmark.circle
}

@test "C3 shows a busy session as idle when the turn already ended" {
  t="$(use_transcript completed-turn)"
  add_session "{\"state\":\"busy\",\"transcriptPath\":\"$t\"}"
  run PLUGIN
  header_is 1 checkmark.circle
}

@test "C3 leaves a session busy when Esc came before any output" {
  t="$(use_transcript esc-before-output)"
  add_session "{\"state\":\"busy\",\"transcriptPath\":\"$t\"}"
  run PLUGIN
  header_is 1 sparkle
}

@test "C3 leaves a session busy while its turn is still running" {
  t="$TEST_TMP/running.jsonl"
  cat "$REPO_ROOT/tests/fixtures/transcripts/denied-permission.jsonl" > "$t"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"Try again with npm ci"}}' \
    '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}}]}}' >> "$t"
  add_session "{\"state\":\"busy\",\"transcriptPath\":\"$t\"}"
  run PLUGIN
  header_is 1 sparkle
}

@test "C3 only reads the last 8 KB of the transcript" {
  t="$TEST_TMP/long.jsonl"
  cat "$REPO_ROOT/tests/fixtures/transcripts/denied-permission.jsonl" > "$t"
  # A long-running turn without its prompt in the tail: the old marker is out of reach.
  filler="$(printf 'x%.0s' $(seq 1 500))"
  for _ in $(seq 1 30); do
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$filler" >> "$t"
  done
  add_session "{\"state\":\"busy\",\"transcriptPath\":\"$t\"}"
  run PLUGIN
  header_is 1 sparkle
}

@test "C3 ignores idle sessions and missing transcripts" {
  add_session '{"state":"busy","transcriptPath":"/nonexistent/t.jsonl"}'
  run PLUGIN
  [ "$status" -eq 0 ]
  header_is 1 sparkle
}

@test "C3 never modifies the state file" {
  t="$(use_transcript denied-permission)"
  add_session "{\"state\":\"busy\",\"transcriptPath\":\"$t\"}"
  before="$(cat "$CLAUDE_AGENTS_STATE_DIR/s1.json")"
  run PLUGIN
  [ "$(cat "$CLAUDE_AGENTS_STATE_DIR/s1.json")" = "$before" ]
}

@test "a corrupt registry file is ignored" {
  add_session '{"state":"busy","updatedAt":1000}'
  printf 'garbage' > "$CLAUDE_AGENTS_REGISTRY_DIR/4242.json"
  run PLUGIN
  [ "$status" -eq 0 ]
  header_is 1 sparkle
}
