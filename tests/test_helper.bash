# Shared setup for bats tests. In each .bats file:
#   setup()    { load test_helper; common_setup; }
#   teardown() { common_teardown; }

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
export REPO_ROOT

common_setup() {
  mkdir -p "$REPO_ROOT/tests/tmp"
  TEST_TMP="$(mktemp -d "$REPO_ROOT/tests/tmp/test.XXXXXX")"
  export TEST_TMP

  # Isolate everything asb touches.
  export HOME="$TEST_TMP/home"
  export ASB_STATE_DIR="$HOME/.claude/agentic-status-bar"
  export ASB_CONFIG="$HOME/.config/agentic-status-bar/config"
  export ASB_REGISTRY_DIR="$HOME/.claude/sessions"
  mkdir -p "$ASB_STATE_DIR" "$(dirname "$ASB_CONFIG")" "$ASB_REGISTRY_DIR"
  # Never talk to a real herdr; tests that need one stub it.
  export ASB_HERDR="$TEST_TMP/no-herdr"
  # The SwiftBar plugin and HOOK run the asb that tests/run.sh builds.
  export ASB_BIN="$REPO_ROOT/.build/debug/asb"

  # Fake commands go first on PATH.
  FAKE_BIN="$TEST_TMP/bin"
  STUB_CALLS="$TEST_TMP/calls"
  mkdir -p "$FAKE_BIN" "$STUB_CALLS"
  export FAKE_BIN STUB_CALLS
  export PATH="$FAKE_BIN:$PATH"
}

common_teardown() {
  [ -n "${TEST_TMP:-}" ] || return 0
  # The hook starts `open` (a stub here) in the background; it may still be writing its call log.
  rm -rf "$TEST_TMP" 2>/dev/null || { sleep 0.3; rm -rf "$TEST_TMP"; }
}

# stub_command NAME [BODY]
# Puts a fake NAME on PATH. Every call appends its arguments as one line to
# $STUB_CALLS/NAME. BODY (shell code) then runs with the original arguments.
stub_command() {
  name="$1"
  body="${2:-}"
  cat > "$FAKE_BIN/$name" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$STUB_CALLS/$name"
$body
STUB
  chmod +x "$FAKE_BIN/$name"
}

# stub_ps — replaces ps with a fake that answers `ps -o FIELD= -p PID` from
# $TEST_TMP/ps-table, one process per line: pid|ppid|comm|args|lstart.
# asb reads the same table (it doesn't run ps) through ASB_PS_TABLE.
stub_ps() {
  : > "$TEST_TMP/ps-table"
  export ASB_PS_TABLE="$TEST_TMP/ps-table"
  stub_command ps '
case " $* " in
  *" -axo "*)
    # Full listing: pid ppid lstart comm
    while IFS="|" read -r p pp comm args lstart; do
      printf "%6s %6s %s %s\n" "$p" "$pp" "$lstart" "$comm"
    done < "'"$TEST_TMP"'/ps-table"
    exit 0 ;;
esac
field=""; pid=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) field="$2"; shift 2 ;;
    -p) pid="$2"; shift 2 ;;
    *) shift ;;
  esac
done
line="$(grep "^$pid|" "'"$TEST_TMP"'/ps-table")" || exit 1
case "$field" in
  ppid=) echo "$line" | cut -d"|" -f2 ;;
  comm=) echo "$line" | cut -d"|" -f3 ;;
  args=) echo "$line" | cut -d"|" -f4 ;;
  lstart=) echo "$line" | cut -d"|" -f5 ;;
esac'
}

# add_process PID PPID COMM ARGS LSTART — adds a row to the fake process table.
add_process() {
  printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" >> "$TEST_TMP/ps-table"
}

# HOOK — the hook (`asb hook`), reading the payload from stdin.
HOOK() {
  "$ASB_BIN" hook
}

# run_hook FIXTURE — feeds tests/fixtures/payloads/FIXTURE.json to the hook.
run_hook() {
  run HOOK < "$REPO_ROOT/tests/fixtures/payloads/$1.json"
}

# state_field FILTER — reads a field from the fixture session's state file.
FIXTURE_SESSION=3f9c2a7e-1b4d-4c8e-9a6f-2d5e8b7c1a90
state_file() {
  printf '%s\n' "$ASB_STATE_DIR/$FIXTURE_SESSION.json"
}
state_field() {
  jq -r "$1" "$(state_file)"
}

# stub_calls NAME — prints the recorded calls of a stub (empty if never called).
stub_calls() {
  cat "$STUB_CALLS/$1" 2>/dev/null || true
}
