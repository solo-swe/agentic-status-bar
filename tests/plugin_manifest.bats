#!/usr/bin/env bats

setup() { load test_helper; }

EVENTS="SessionStart UserPromptSubmit PreToolUse PostToolUse Notification Stop SubagentStart SubagentStop SessionEnd"

@test "plugin.json is valid and names the plugin" {
  run jq -r '.name' "$REPO_ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
  [ "$output" = claude-agents ]
  run jq -r '.version' "$REPO_ROOT/.claude-plugin/plugin.json"
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "hooks.json registers the state hook, async, for every event" {
  for event in $EVENTS; do
    cmd="$(jq -r --arg e "$event" '.hooks[$e][0].hooks[0].command' "$REPO_ROOT/hooks/hooks.json")"
    [ "$cmd" = '${CLAUDE_PLUGIN_ROOT}/hooks/state-hook.sh' ] || { echo "$event: $cmd"; false; }
    async="$(jq -r --arg e "$event" '.hooks[$e][0].hooks[0].async' "$REPO_ROOT/hooks/hooks.json")"
    [ "$async" = true ] || { echo "$event not async"; false; }
  done
}

@test "hooks.json registers no other events" {
  run jq -r '.hooks | keys | length' "$REPO_ROOT/hooks/hooks.json"
  [ "$output" -eq 9 ]
}

@test "the hook script is executable" {
  [ -x "$REPO_ROOT/hooks/state-hook.sh" ]
}
