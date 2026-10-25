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

@test "a corrupt registry file is ignored" {
  add_session '{"state":"busy","updatedAt":1000}'
  printf 'garbage' > "$CLAUDE_AGENTS_REGISTRY_DIR/4242.json"
  run PLUGIN
  [ "$status" -eq 0 ]
  header_is 1 sparkle
}
