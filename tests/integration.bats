#!/usr/bin/env bats
# Hook events in, SwiftBar menu out.

setup() {
  load test_helper
  common_setup
  stub_ps
  add_process 5000 4242 /bin/sh "sh -c state-hook.sh" "Mon Oct 19 09:12:04 2026"
  add_process 4242 1 claude "claude" "Mon Oct 19 09:12:03 2026"
  export CLAUDE_STATUSBAR_PARENT_PID=5000
  export CLAUDE_CODE_ENTRYPOINT=cli
  # Never open real URLs from tests.
  stub_command open
}
teardown() { common_teardown; }

PLUGIN() { "$REPO_ROOT/swiftbar/swiftbar-claudecode-minimal.5s.sh" "$@"; }

@test "a permission prompt turns the menu bar red with the session's row" {
  run_hook SessionStart
  run_hook UserPromptSubmit
  run_hook PreToolUse
  run_hook Notification-permission_prompt
  run PLUGIN
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "1 | sfimage=exclamationmark.circle.fill "* ]]
  [[ "$output" == *"● api-gateway — Add rate limiting to the auth"*"…  permission · "* ]]
}

@test "after Stop the session shows as idle" {
  run_hook SessionStart
  run_hook UserPromptSubmit
  run_hook Stop
  run PLUGIN
  [[ "${lines[0]}" == "1 | sfimage=checkmark.circle "* ]]
  [[ "$output" == *"idle · "* ]]
}

@test "when the claude process exits, the session disappears" {
  run_hook SessionStart
  run_hook UserPromptSubmit
  : > "$TEST_TMP/ps-table"
  run PLUGIN
  [[ "${lines[0]}" == " | sfimage=sparkle "* ]]
  [ ! -e "$(state_file)" ]
}

@test "after SessionEnd the session disappears" {
  run_hook SessionStart
  run_hook SessionEnd
  run PLUGIN
  [[ "$output" == *"No Claude Code sessions"* ]]
}
