#!/usr/bin/env bats

setup() {
  load test_helper
  common_setup
  export CLAUDE_STATUSBAR_SETTINGS="$HOME/.claude/settings.json"
  export CLAUDE_STATUSBAR_SWIFTBAR_DIR="$HOME/swiftbar-plugins"
  mkdir -p "$HOME/.claude"
  cp "$REPO_ROOT/tests/fixtures/settings.json" "$CLAUDE_STATUSBAR_SETTINGS"
  # Never read the real SwiftBar defaults.
  stub_command defaults 'exit 1'
}
teardown() { common_teardown; }

EVENTS="SessionStart UserPromptSubmit PreToolUse PostToolUse Notification Stop SubagentStart SubagentStop SessionEnd"
OURS='endswith("# swiftbar-claudecode-minimal")'

ours_count() { jq "[.hooks[]?[]?.hooks[]? | select(.command | $OURS)] | length" "$CLAUDE_STATUSBAR_SETTINGS"; }

@test "install adds one async state hook per event" {
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  for event in $EVENTS; do
    n="$(jq --arg e "$event" "[.hooks[\$e][]?.hooks[]? | select(.command | $OURS)] | length" "$CLAUDE_STATUSBAR_SETTINGS")"
    [ "$n" -eq 1 ] || { echo "$event: $n"; false; }
  done
  cmd="$(jq -r ".hooks.Stop[] | .hooks[] | select(.command | $OURS) | .command" "$CLAUDE_STATUSBAR_SETTINGS")"
  [ "$cmd" = "'$REPO_ROOT/hooks/state-hook.sh' # swiftbar-claudecode-minimal" ]
  [ "$(jq -r ".hooks.Stop[] | .hooks[] | select(.command | $OURS) | .async" "$CLAUDE_STATUSBAR_SETTINGS")" = true ]
}

@test "install keeps existing hooks and settings unchanged and in order" {
  run "$REPO_ROOT/install.sh"
  [ "$(jq -c '.permissions' "$CLAUDE_STATUSBAR_SETTINGS")" = "$(jq -c '.permissions' "$REPO_ROOT/tests/fixtures/settings.json")" ]
  [ "$(jq -c '.hooks.SessionStart[0]' "$CLAUDE_STATUSBAR_SETTINGS")" = "$(jq -c '.hooks.SessionStart[0]' "$REPO_ROOT/tests/fixtures/settings.json")" ]
  [ "$(jq -c '.hooks.PostToolUse[0]' "$CLAUDE_STATUSBAR_SETTINGS")" = "$(jq -c '.hooks.PostToolUse[0]' "$REPO_ROOT/tests/fixtures/settings.json")" ]
}

@test "install backs up the settings file" {
  run "$REPO_ROOT/install.sh"
  backup="$(ls "$HOME/.claude"/settings.json.bak-swiftbar-claudecode-minimal-*)"
  cmp "$backup" "$REPO_ROOT/tests/fixtures/settings.json"
}

@test "install twice adds nothing the second time" {
  run "$REPO_ROOT/install.sh"
  first="$(jq -c . "$CLAUDE_STATUSBAR_SETTINGS")"
  sleep 1
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -c . "$CLAUDE_STATUSBAR_SETTINGS")" = "$first" ]
  [ "$(ours_count)" -eq 9 ]
}

@test "install creates a settings file when there is none" {
  rm "$CLAUDE_STATUSBAR_SETTINGS"
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ "$(ours_count)" -eq 9 ]
}

@test "install refuses to touch an invalid settings file" {
  printf 'not json' > "$CLAUDE_STATUSBAR_SETTINGS"
  run "$REPO_ROOT/install.sh"
  [ "$status" -ne 0 ]
  [ "$(cat "$CLAUDE_STATUSBAR_SETTINGS")" = "not json" ]
}

@test "install links the SwiftBar plugin" {
  run "$REPO_ROOT/install.sh"
  [ -L "$CLAUDE_STATUSBAR_SWIFTBAR_DIR/swiftbar-claudecode-minimal.5s.sh" ]
  [ "$(readlink "$CLAUDE_STATUSBAR_SWIFTBAR_DIR/swiftbar-claudecode-minimal.5s.sh")" = "$REPO_ROOT/swiftbar/swiftbar-claudecode-minimal.5s.sh" ]
}

@test "install uses SwiftBar's configured plugin folder" {
  unset CLAUDE_STATUSBAR_SWIFTBAR_DIR
  stub_command defaults "echo '$HOME/from-defaults'"
  run "$REPO_ROOT/install.sh"
  [ -L "$HOME/from-defaults/swiftbar-claudecode-minimal.5s.sh" ]
}

# --- uninstall ------------------------------------------------------------

@test "uninstall restores the settings to exactly what they were" {
  run "$REPO_ROOT/install.sh"
  run "$REPO_ROOT/uninstall.sh" < /dev/null
  [ "$status" -eq 0 ]
  [ "$(jq -S -c . "$CLAUDE_STATUSBAR_SETTINGS")" = "$(jq -S -c . "$REPO_ROOT/tests/fixtures/settings.json")" ]
}

@test "uninstall keeps a group that mixes our hook with others" {
  run "$REPO_ROOT/install.sh"
  # Someone added their own hook to the group install created.
  jq '(.hooks.Stop[] | select(any(.hooks[]; .command | endswith("# swiftbar-claudecode-minimal"))) | .hooks) += [{"type":"command","command":"say done"}]' \
    "$CLAUDE_STATUSBAR_SETTINGS" > "$TEST_TMP/s.json" && mv "$TEST_TMP/s.json" "$CLAUDE_STATUSBAR_SETTINGS"
  run "$REPO_ROOT/uninstall.sh" < /dev/null
  [ "$(jq -c '.hooks.Stop' "$CLAUDE_STATUSBAR_SETTINGS")" = '[{"hooks":[{"type":"command","command":"say done"}]}]' ]
  [ "$(ours_count)" -eq 0 ]
}

@test "uninstall removes the hooks key when only ours were there" {
  printf '{"model":"opus"}\n' > "$CLAUDE_STATUSBAR_SETTINGS"
  run "$REPO_ROOT/install.sh"
  run "$REPO_ROOT/uninstall.sh" < /dev/null
  [ "$(jq -c . "$CLAUDE_STATUSBAR_SETTINGS")" = '{"model":"opus"}' ]
}

@test "uninstall removes our SwiftBar link but not someone else's" {
  run "$REPO_ROOT/install.sh"
  run "$REPO_ROOT/uninstall.sh" < /dev/null
  [ ! -e "$CLAUDE_STATUSBAR_SWIFTBAR_DIR/swiftbar-claudecode-minimal.5s.sh" ]

  ln -s /somewhere/else.sh "$CLAUDE_STATUSBAR_SWIFTBAR_DIR/swiftbar-claudecode-minimal.5s.sh"
  run "$REPO_ROOT/uninstall.sh" < /dev/null
  [ -L "$CLAUDE_STATUSBAR_SWIFTBAR_DIR/swiftbar-claudecode-minimal.5s.sh" ]
}

@test "uninstall keeps state and config unless asked to purge" {
  run "$REPO_ROOT/install.sh"
  printf 'icon=bolt\n' > "$CLAUDE_STATUSBAR_CONFIG"
  printf '{}' > "$CLAUDE_STATUSBAR_STATE_DIR/s1.json"
  run "$REPO_ROOT/uninstall.sh" < /dev/null
  [ -e "$CLAUDE_STATUSBAR_CONFIG" ]
  [ -e "$CLAUDE_STATUSBAR_STATE_DIR/s1.json" ]

  run "$REPO_ROOT/uninstall.sh" --purge < /dev/null
  [ ! -e "$CLAUDE_STATUSBAR_CONFIG" ]
  [ ! -e "$CLAUDE_STATUSBAR_STATE_DIR" ]
}

@test "uninstall removes the start-at-login item" {
  item="$HOME/Library/LaunchAgents/swiftbar-claudecode-minimal.start-swiftbar.plist"
  other="$HOME/Library/LaunchAgents/com.example.other.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  printf 'x' > "$item"
  printf 'x' > "$other"
  run "$REPO_ROOT/uninstall.sh" < /dev/null
  [ "$status" -eq 0 ]
  [ ! -e "$item" ]
  [ -e "$other" ]
}

@test "uninstall twice is harmless" {
  run "$REPO_ROOT/install.sh"
  run "$REPO_ROOT/uninstall.sh" < /dev/null
  first="$(jq -S -c . "$CLAUDE_STATUSBAR_SETTINGS")"
  run "$REPO_ROOT/uninstall.sh" < /dev/null
  [ "$status" -eq 0 ]
  [ "$(jq -S -c . "$CLAUDE_STATUSBAR_SETTINGS")" = "$first" ]
}

@test "install skips the link when no plugin folder is known" {
  unset CLAUDE_STATUSBAR_SWIFTBAR_DIR
  run "$REPO_ROOT/install.sh" < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped the SwiftBar link"* ]]
}
