#!/bin/sh
# Times `asb hook` (median under 10 ms; the shell hook took 19 to 20 ms) and `asb snapshot`
# on 10 sessions (under 30 ms). Exits 1 if a target is missed.
# Run it with: tests/bench.sh

cd "$(dirname "$0")/.." || exit 1
repo="$(pwd)"

HOOK_RUNS=50
HOOK_TARGET_MS=10
SNAPSHOT_RUNS=20
SNAPSHOT_TARGET_MS=30

tmp="$(mktemp -d "${TMPDIR:-/tmp}/agentic-status-bar-bench.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
export ASB_STATE_DIR="$HOME/.claude/agentic-status-bar"
export ASB_CONFIG="$HOME/.config/agentic-status-bar/config"
export ASB_REGISTRY_DIR="$HOME/.claude/sessions"
export ASB_HERDR="$tmp/no-herdr"
mkdir -p "$ASB_STATE_DIR" "$ASB_REGISTRY_DIR"

now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'; }

# Ten realistic sessions: mixed states, transcripts, one live pid with a registry entry.
pid=$$
lstart="$(ps -o lstart= -p "$pid" | sed 's/^ *//;s/ *$//')"
now="$(now_ms)"
for i in 0 1 2 3 4 5 6 7 8 9; do
  case $((i % 4)) in
    0) state=waiting ;;
    1) state=idle ;;
    *) state=busy ;;
  esac
  transcript="$tmp/t$i.jsonl"
  cat "$repo/tests/fixtures/transcripts/completed-turn.jsonl" > "$transcript"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' \
      "Working through the change set step by step, checking each file." >> "$transcript"
  done
  printf '{"v":1,"sessionId":"bench-%s","state":"%s","reason":"permission","cwd":"/Users/alex/code/project-%s","kind":"interactive","pid":%s,"procStart":"%s","transcriptPath":"%s","promptPreview":"Refactor module %s","updatedAt":%s,"stateSince":%s,"subagents":{"a%s":{"type":"Explore","since":%s}}}\n' \
    "$i" "$state" "$i" "$pid" "$lstart" "$transcript" "$i" "$now" "$now" "$i" "$now" \
    > "$ASB_STATE_DIR/bench-$i.json"
done
printf '{"pid":%s,"sessionId":"bench-0","status":"waiting","waitingFor":"permission prompt","statusUpdatedAt":%s}\n' \
  "$pid" "$now" > "$ASB_REGISTRY_DIR/$pid.json"

# time_runs N SHELL_COMMAND — prints one duration in ms per run, timed inside a
# single perl process so the timer's own startup isn't counted.
time_runs() {
  perl -MTime::HiRes=time -e '
    my ($n, $cmd) = @ARGV;
    for (1 .. $n) {
      my $t = time;
      system("sh", "-c", "$cmd >/dev/null 2>&1");
      printf "%d\n", (time - $t) * 1000;
    }' "$1" "$2"
}

# report NAME TARGET — reads durations on stdin, prints median and p95, fails over target.
report() {
  sort -n > "$tmp/times"
  _count="$(wc -l < "$tmp/times" | tr -d ' ')"
  _median="$(sed -n "$(( (_count + 1) / 2 ))p" "$tmp/times")"
  _p95="$(sed -n "$(( (_count * 95 + 99) / 100 ))p" "$tmp/times")"
  if [ "$_median" -le "$2" ]; then _verdict=ok; else _verdict=FAIL; fi
  printf '%-7s median %4s ms  p95 %4s ms  (target %s ms)  %s\n' "$1" "$_median" "$_p95" "$2" "$_verdict"
  [ "$_verdict" = ok ]
}

# asb, built for release (as it ships).
if ! swift build -c release --product asb >"$tmp/build.log" 2>&1; then
  echo "swift build failed:" >&2
  cat "$tmp/build.log" >&2
  exit 1
fi
asb="$repo/.build/release/asb"

status=0
# The hook gets a real Claude-style payload; its state file is the 11th session.
time_runs "$HOOK_RUNS" "'$asb' hook < '$repo/tests/fixtures/payloads/PreToolUse.json'" \
  | report hook "$HOOK_TARGET_MS" || status=1
time_runs "$SNAPSHOT_RUNS" "'$asb' snapshot --json" | report snapshot "$SNAPSHOT_TARGET_MS" || status=1
exit "$status"
