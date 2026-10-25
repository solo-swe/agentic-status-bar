#!/bin/sh
# shellcheck source-path=SCRIPTDIR disable=SC2016
# (SC2016: jq programs use $variables inside single quotes on purpose.)
#
# <xbar.title>Claude Agents</xbar.title>
# <xbar.version>v0.1.0</xbar.version>
# <xbar.author>Hakan Serce</xbar.author>
# <xbar.desc>Shows in one menu-bar item whether any running Claude Code agent needs you.</xbar.desc>
# <xbar.dependencies>jq</xbar.dependencies>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisappearPlugin>true</swiftbar.hideDisappearPlugin>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
#
# Reads the per-session state files written by hooks/state-hook.sh and renders
# them for SwiftBar. Run with arguments, it performs a menu action instead.

# Highest state file version this plugin understands.
MAX_STATE_VERSION=1

# Resolve our own directory, following symlinks (SwiftBar runs a symlink).
self="$0"
while [ -L "$self" ]; do
  link="$(readlink "$self")"
  case "$link" in
    /*) self="$link" ;;
    *) self="$(dirname "$self")/$link" ;;
  esac
done
plugin_dir="$(cd "$(dirname "$self")" && pwd)" || exit 1
# shellcheck source=../lib/common.sh
. "$plugin_dir/../lib/common.sh" || exit 1

# load_sessions — prints {"sessions": [...], "invalid": N} for all state files.
# Files that don't parse, aren't objects or have an unknown version count as invalid.
load_sessions() {
  set -- "$cfg_state_dir"/*.json
  if [ ! -e "$1" ]; then
    printf '{"sessions":[],"invalid":0}'
    return
  fi
  # One "path<TAB>content" line per file, so a file without a trailing newline
  # can't run into the next one.
  for _f in "$@"; do
    printf '%s\t' "$_f"
    tr -d '\n' < "$_f"
    printf '\n'
  done | "$JQ" -c -R -n --argjson maxv "$MAX_STATE_VERSION" '
    [inputs | index("\t") as $i
      | {file: .[0:$i], s: (.[$i + 1:] | try fromjson catch null)}]
    | map(.ok = ((.s | type) == "object" and ((.s.v // 0) | type) == "number"
                 and .s.v >= 1 and .s.v <= $maxv))
    | {sessions: [.[] | select(.ok) | .s + {file: .file}],
       invalid: ([.[] | select(.ok | not)] | length)}
  '
}

# take_snapshot FILE — one process table per run: pid, ppid, lstart (5 words), comm.
take_snapshot() {
  ps -axo pid=,ppid=,lstart=,comm= > "$1" 2>/dev/null
}

# The checks, in order. Each session gets a display state (`shown`); dead ones
# are marked and dropped. Checks never write state files.
CHECKS_JQ='
  def norm: gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ");

  # pid -> {ppid, lstart, comm} from `ps -axo pid=,ppid=,lstart=,comm=`
  def procs:
    split("\n")
    | map(select(test("\\S")) | sub("^\\s+"; "") | [splits("\\s+")])
    | map({key: .[0], value: {ppid: .[1], lstart: (.[2:7] | join(" ")), comm: (.[7:] | join(" "))}})
    | from_entries;

  # C1: the claude process must still exist and have the same start time.
  def alive($P):
    if .pid == null then true
    else $P[.pid | tostring] as $p
      | $p != null and (.procStart == null or ($p.lstart | norm) == (.procStart | norm))
    end;

  ($ps | procs) as $P
  | .sessions |= map(.shown = .state | .alive = alive($P))
  | .dead = [.sessions[] | select(.alive | not) | .file]
  | .sessions |= map(select(.alive) | del(.alive))
'

# apply_checks DATA PS_FILE — runs the checks and prints the updated data.
apply_checks() {
  printf '%s' "$1" | "$JQ" -c --rawfile ps "$2" "$CHECKS_JQ"
}

# remove_dead DATA — deletes the state files of sessions found dead.
remove_dead() {
  printf '%s' "$1" | "$JQ" -r '.dead[]' | while IFS= read -r _f; do
    case "$_f" in
      "$cfg_state_dir"/*.json) rm -f "$_f" ;;
    esac
  done
}

render_jq_missing() {
  echo "⚠︎ | sfimage=exclamationmark.triangle"
  echo "---"
  echo "claude-agents needs jq"
  echo "Install it with: brew install jq | color=gray"
}

# render DATA — prints the SwiftBar menu for the loaded sessions.
render() {
  printf '%s' "$1" | "$JQ" -r '
    if .invalid > 0 then
      "⚠︎ \(.sessions | length) | sfimage=exclamationmark.triangle",
      "---",
      "\(.invalid) state file(s) could not be read | color=gray"
    else
      "✳ \(.sessions | length)",
      "---"
    end,
    "\(.sessions | length) session(s)"
  '
}

main() {
  load_config
  JQ="$(find_jq)"
  if [ -z "$JQ" ]; then
    render_jq_missing
    return 0
  fi

  ps_file="$(mktemp "${TMPDIR:-/tmp}/claude-agents-ps.XXXXXX")" || return 1
  trap 'rm -f "$ps_file"' EXIT
  take_snapshot "$ps_file"

  data="$(apply_checks "$(load_sessions)" "$ps_file")"
  remove_dead "$data"
  render "$data"
}

main "$@"
