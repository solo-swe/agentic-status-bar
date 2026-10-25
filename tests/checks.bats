#!/usr/bin/env bats
# Reconciliation checks C2-C5 (C1 is in plugin.bats).

setup() {
  load test_helper
  common_setup
  stub_ps
  add_process 4242 1 claude claude "Mon Oct 19 09:12:03 2026"
  # Fixtures use small timestamps; C5 is switched on only by its own tests.
  printf 'stale_minutes=0\n' > "$CLAUDE_STATUSBAR_CONFIG"
}
teardown() { common_teardown; }

PLUGIN() { "$REPO_ROOT/swiftbar/swiftbar-claudecode-minimal.5s.sh" "$@"; }

# add_session JSON — the state file of a live session (pid 4242) merged with JSON.
add_session() {
  printf '%s' "$1" | jq -c '{v: 1, sessionId: "s1", pid: 4242, procStart: "Mon Oct 19 09:12:03 2026", cwd: "/x/proj", updatedAt: 1000, stateSince: 1000} + .' \
    > "$CLAUDE_STATUSBAR_STATE_DIR/s1.json"
}

# add_registry JSON — Claude Code's registry entry for pid 4242 merged with JSON.
add_registry() {
  printf '%s' "$1" | jq -c '{pid: 4242, sessionId: "s1"} + .' > "$CLAUDE_STATUSBAR_REGISTRY_DIR/4242.json"
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
  [ "$(grep -c '^\[registry-schema\]' "$CLAUDE_STATUSBAR_STATE_DIR/plugin.log")" -eq 1 ]
}

@test "C2 is off when use_registry=0" {
  printf 'use_registry=0\nstale_minutes=0\n' > "$CLAUDE_STATUSBAR_CONFIG"
  add_session '{"state":"busy","updatedAt":1000}'
  add_registry '{"status":"idle","statusUpdatedAt":2000}'
  run PLUGIN
  header_is 1 sparkle
}

@test "C2 never modifies the state file" {
  add_session '{"state":"busy","updatedAt":1000}'
  add_registry '{"status":"idle","statusUpdatedAt":2000}'
  before="$(cat "$CLAUDE_STATUSBAR_STATE_DIR/s1.json")"
  run PLUGIN
  [ "$(cat "$CLAUDE_STATUSBAR_STATE_DIR/s1.json")" = "$before" ]
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
  before="$(cat "$CLAUDE_STATUSBAR_STATE_DIR/s1.json")"
  run PLUGIN
  [ "$(cat "$CLAUDE_STATUSBAR_STATE_DIR/s1.json")" = "$before" ]
}

# --- C4 approved tool -----------------------------------------------------

# lstart_at EPOCH_SECONDS — a ps-style local start time.
lstart_at() { date -r "$1" '+%a %b %e %H:%M:%S %Y'; }

@test "C4 shows a waiting session as busy when a tool started after the prompt" {
  prompt=$(( $(date +%s) - 60 ))
  add_session "{\"state\":\"waiting\",\"reason\":\"permission\",\"stateSince\":$(( prompt * 1000 ))}"
  add_process 7001 4242 /bin/zsh "zsh -c npm test" "$(lstart_at $(( prompt + 5 )))"
  run PLUGIN
  header_is 1 sparkle
  [[ "$output" == *"working · "* ]]
}

@test "C4 ignores children started before the prompt (MCP servers)" {
  prompt=$(( $(date +%s) - 60 ))
  add_session "{\"state\":\"waiting\",\"reason\":\"permission\",\"stateSince\":$(( prompt * 1000 ))}"
  add_process 7002 4242 node "node mcp-server.js" "$(lstart_at $(( prompt - 3600 )))"
  run PLUGIN
  header_is 1 exclamationmark.circle.fill
}

@test "C4 ignores caffeinate" {
  prompt=$(( $(date +%s) - 60 ))
  add_session "{\"state\":\"waiting\",\"reason\":\"permission\",\"stateSince\":$(( prompt * 1000 ))}"
  add_process 7003 4242 /usr/bin/caffeinate "caffeinate -i" "$(lstart_at $(( prompt + 5 )))"
  run PLUGIN
  header_is 1 exclamationmark.circle.fill
}

@test "C4 ignores children of other processes" {
  prompt=$(( $(date +%s) - 60 ))
  add_session "{\"state\":\"waiting\",\"reason\":\"permission\",\"stateSince\":$(( prompt * 1000 ))}"
  add_process 7004 9999 /bin/zsh "zsh" "$(lstart_at $(( prompt + 5 )))"
  run PLUGIN
  header_is 1 exclamationmark.circle.fill
}

# --- C5 staleness ---------------------------------------------------------

minutes_ago_ms() { echo $(( ($(date +%s) - $1 * 60) * 1000 )); }
enable_c5() { printf 'stale_minutes=30\n' > "$CLAUDE_STATUSBAR_CONFIG"; }

@test "C5 marks a busy session with no activity past the threshold as uncertain" {
  enable_c5
  add_session "{\"state\":\"busy\",\"updatedAt\":$(minutes_ago_ms 45),\"stateSince\":$(minutes_ago_ms 45)}"
  run PLUGIN
  header_is 1 questionmark.circle
  [[ "$output" == *"? proj "*"no activity · 45m"* ]]
}

@test "C5 leaves a busy session alone within the threshold" {
  enable_c5
  add_session "{\"state\":\"busy\",\"updatedAt\":$(minutes_ago_ms 10),\"stateSince\":$(minutes_ago_ms 10)}"
  run PLUGIN
  header_is 1 sparkle
}

@test "C5 counts a recent transcript write as activity" {
  enable_c5
  printf '{"type":"assistant"}\n' > "$TEST_TMP/active.jsonl"
  add_session "{\"state\":\"busy\",\"updatedAt\":$(minutes_ago_ms 45),\"transcriptPath\":\"$TEST_TMP/active.jsonl\"}"
  run PLUGIN
  header_is 1 sparkle
}

@test "C5 counts a recently started child process as activity" {
  enable_c5
  add_session "{\"state\":\"busy\",\"updatedAt\":$(minutes_ago_ms 45)}"
  add_process 7005 4242 /bin/zsh "zsh -c make" "$(lstart_at $(( $(date +%s) - 120 )))"
  run PLUGIN
  header_is 1 sparkle
}

@test "C5 uses the configured threshold" {
  printf 'stale_minutes=60\n' > "$CLAUDE_STATUSBAR_CONFIG"
  add_session "{\"state\":\"busy\",\"updatedAt\":$(minutes_ago_ms 45)}"
  run PLUGIN
  header_is 1 sparkle
}

@test "C5 is off when stale_minutes=0" {
  printf 'stale_minutes=0\n' > "$CLAUDE_STATUSBAR_CONFIG"
  add_session "{\"state\":\"busy\",\"updatedAt\":$(minutes_ago_ms 600)}"
  run PLUGIN
  header_is 1 sparkle
}

@test "C5 never marks waiting or idle sessions as stale" {
  enable_c5
  add_session "{\"state\":\"waiting\",\"reason\":\"permission\",\"updatedAt\":$(minutes_ago_ms 300),\"stateSince\":$(minutes_ago_ms 300)}"
  run PLUGIN
  header_is 1 exclamationmark.circle.fill
  add_session "{\"state\":\"idle\",\"updatedAt\":$(minutes_ago_ms 300)}"
  run PLUGIN
  header_is 1 checkmark.circle
}

@test "uncertain ranks below idle and above busy" {
  enable_c5
  add_session "{\"state\":\"busy\",\"updatedAt\":$(minutes_ago_ms 45)}"
  printf '{"v":1,"sessionId":"s2","state":"busy","cwd":"/x/fresh","updatedAt":%s}' "$(minutes_ago_ms 1)" > "$CLAUDE_STATUSBAR_STATE_DIR/s2.json"
  run PLUGIN
  header_is 1 questionmark.circle
  printf '{"v":1,"sessionId":"s3","state":"idle","cwd":"/x/done"}' > "$CLAUDE_STATUSBAR_STATE_DIR/s3.json"
  run PLUGIN
  header_is 1 checkmark.circle
}

@test "C4 and C5 never modify the state file" {
  enable_c5
  prompt=$(( $(date +%s) - 60 ))
  add_session "{\"state\":\"waiting\",\"reason\":\"permission\",\"stateSince\":$(( prompt * 1000 ))}"
  add_process 7001 4242 /bin/zsh "zsh" "$(lstart_at $(( prompt + 5 )))"
  before="$(cat "$CLAUDE_STATUSBAR_STATE_DIR/s1.json")"
  run PLUGIN
  [[ "$output" == *"working · "* ]]
  [ "$(cat "$CLAUDE_STATUSBAR_STATE_DIR/s1.json")" = "$before" ]

  add_session "{\"state\":\"busy\",\"updatedAt\":$(minutes_ago_ms 45)}"
  : > "$TEST_TMP/ps-table"
  add_process 4242 1 claude claude "Mon Oct 19 09:12:03 2026"
  before="$(cat "$CLAUDE_STATUSBAR_STATE_DIR/s1.json")"
  run PLUGIN
  [[ "$output" == *"no activity · "* ]]
  [ "$(cat "$CLAUDE_STATUSBAR_STATE_DIR/s1.json")" = "$before" ]
}

@test "a corrupt registry file is ignored" {
  add_session '{"state":"busy","updatedAt":1000}'
  printf 'garbage' > "$CLAUDE_STATUSBAR_REGISTRY_DIR/4242.json"
  run PLUGIN
  [ "$status" -eq 0 ]
  header_is 1 sparkle
}
