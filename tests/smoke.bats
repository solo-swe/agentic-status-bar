#!/usr/bin/env bats

setup() { load test_helper; common_setup; }
teardown() { common_teardown; }

@test "HOME and state dirs are isolated in a temp dir" {
  [[ "$HOME" == "$TEST_TMP"/* ]]
  [ -d "$ASB_STATE_DIR" ]
  [ -d "$ASB_REGISTRY_DIR" ]
  [ -d "$(dirname "$ASB_CONFIG")" ]
}

@test "stubbed commands shadow real ones and record their calls" {
  stub_command ps 'echo fake-ps'
  run ps -axo pid=
  [ "$status" -eq 0 ]
  [ "$output" = "fake-ps" ]
  [ "$(stub_calls ps)" = "-axo pid=" ]
}

@test "stub_calls is empty for a stub that was never called" {
  stub_command herdr
  [ -z "$(stub_calls herdr)" ]
}
