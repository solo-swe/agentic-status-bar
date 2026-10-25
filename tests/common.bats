#!/usr/bin/env bats

setup() {
  load test_helper
  common_setup
  # shellcheck source=../lib/common.sh
  . "$REPO_ROOT/lib/common.sh"
}
teardown() { common_teardown; }

@test "load_config uses defaults when there is no config file" {
  unset CLAUDE_STATUSBAR_STATE_DIR
  load_config
  [ "$cfg_show_interactive" = 1 ]
  [ "$cfg_show_headless" = 1 ]
  [ "$cfg_show_subagents" = 1 ]
  [ "$cfg_show_ide" = 1 ]
  [ "$cfg_stale_minutes" = 30 ]
  [ "$cfg_use_registry" = 1 ]
  [ "$cfg_instant_refresh" = 1 ]
  [ -z "$cfg_icon" ]
  [ "$cfg_store_prompt_preview" = 1 ]
  [ "$cfg_state_dir" = "$HOME/.claude/swiftbar-claudecode-minimal" ]
  [ "$cfg_theme" = default ]
  [ -z "$cfg_icon_idle" ]
  [ -z "$cfg_color_idle" ]
}

@test "color keys take #RRGGBB or a light,dark pair, nothing else" {
  cat > "$CLAUDE_STATUSBAR_CONFIG" <<'EOF'
color_idle=#123abc,#FFFFFF
color_busy=#00FF00
color_waiting=red
color_muted=#12345
color_none=#123456;touch x
icon_idle=moon.zzz
theme=high_contrast
EOF
  load_config
  [ "$cfg_color_idle" = "#123abc,#FFFFFF" ]
  [ "$cfg_color_busy" = "#00FF00" ]
  [ -z "$cfg_color_waiting" ]
  [ -z "$cfg_color_muted" ]
  [ -z "$cfg_color_none" ]
  [ "$cfg_icon_idle" = moon.zzz ]
  [ "$cfg_theme" = high_contrast ]
  run set_config color_idle 'red'
  [ "$status" -ne 0 ]
  set_config color_idle '#000000,#FFFFFF'
  grep -q '^color_idle=#000000,#FFFFFF$' "$CLAUDE_STATUSBAR_CONFIG"
}

@test "load_config reads overrides from the config file" {
  unset CLAUDE_STATUSBAR_STATE_DIR
  printf 'stale_minutes=10\n# a comment\nicon=bolt\nstate_dir=~/agents\n' > "$CLAUDE_STATUSBAR_CONFIG"
  load_config
  [ "$cfg_stale_minutes" = 10 ]
  [ "$cfg_icon" = bolt ]
  [ "$cfg_state_dir" = "$HOME/agents" ]
  [ "$cfg_use_registry" = 1 ]
}

@test "CLAUDE_STATUSBAR_STATE_DIR wins over the config file" {
  printf 'state_dir=/elsewhere\n' > "$CLAUDE_STATUSBAR_CONFIG"
  load_config
  [ "$cfg_state_dir" = "$CLAUDE_STATUSBAR_STATE_DIR" ]
}

@test "load_config ignores unknown keys and never executes values" {
  cat > "$CLAUDE_STATUSBAR_CONFIG" <<EOF
evil=1
icon=\$(touch $TEST_TMP/pwned)
stale_minutes=\`touch $TEST_TMP/pwned2\`
use_registry=0;touch $TEST_TMP/pwned3
EOF
  load_config
  [ ! -e "$TEST_TMP/pwned" ]
  [ ! -e "$TEST_TMP/pwned2" ]
  [ ! -e "$TEST_TMP/pwned3" ]
  [ -z "$cfg_icon" ]
  [ "$cfg_stale_minutes" = 30 ]
  [ "$cfg_use_registry" = 1 ]
  [ -z "${cfg_evil:-}" ]
}

@test "set_config changes one key and keeps the others" {
  printf 'icon=bolt\nstale_minutes=10\n' > "$CLAUDE_STATUSBAR_CONFIG"
  set_config stale_minutes 60
  load_config
  [ "$cfg_stale_minutes" = 60 ]
  [ "$cfg_icon" = bolt ]
  [ "$(grep -c '^stale_minutes=' "$CLAUDE_STATUSBAR_CONFIG")" -eq 1 ]
}

@test "set_config creates the config file and rejects unknown keys or bad values" {
  rm -f "$CLAUDE_STATUSBAR_CONFIG"
  set_config show_headless 0
  [ "$(cat "$CLAUDE_STATUSBAR_CONFIG")" = "show_headless=0" ]
  run set_config evil 1
  [ "$status" -ne 0 ]
  run set_config icon 'a;b'
  [ "$status" -ne 0 ]
  [ "$(cat "$CLAUDE_STATUSBAR_CONFIG")" = "show_headless=0" ]
}

@test "now_ms returns epoch milliseconds" {
  run now_ms
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{13}$ ]]
}

@test "atomic_write writes exact content and leaves no temp file" {
  printf 'line one\nline two\n' | atomic_write "$TEST_TMP/out.json"
  [ "$(cat "$TEST_TMP/out.json")" = "$(printf 'line one\nline two')" ]
  [ -z "$(find "$TEST_TMP" -name 'out.json.tmp.*')" ]
}

@test "find_jq prints an executable jq path" {
  run find_jq
  [ "$status" -eq 0 ]
  [ -x "$output" ]
}

@test "CLAUDE_STATUSBAR_JQ overrides the jq lookup" {
  CLAUDE_STATUSBAR_JQ=/nonexistent/jq run find_jq
  [ -z "$output" ]
  CLAUDE_STATUSBAR_JQ=/usr/bin/jq run find_jq
  [ "$output" = /usr/bin/jq ]
}

@test "log_once writes each key only once" {
  load_config
  log_once registry-schema "first message"
  log_once registry-schema "second message"
  log_once other "another"
  [ "$(grep -c '^\[registry-schema\] ' "$cfg_state_dir/plugin.log")" -eq 1 ]
  grep -q 'first message' "$cfg_state_dir/plugin.log"
  grep -q '^\[other\] ' "$cfg_state_dir/plugin.log"
}
