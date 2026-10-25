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

# Menu-bar colors as light,dark pairs.
COLORS='{
  "waiting": "#D70015,#FF453A",
  "idle": "#B25000,#FFD60A",
  "uncertain": "#8E8E93,#98989D",
  "busy": "#6E6E73,#AEAEB2",
  "none": "#C7C7CC,#48484A",
  "warning": "#B25000,#FFD60A"
}'

# The menu-bar line: the most urgent state (waiting > idle > uncertain > busy)
# and the number of sessions in it. Each state has its own symbol, so color is
# never the only signal.
HEADER_JQ='
  def count($st): [.sessions[] | select(.shown == $st)] | length;
  def title($text; $symbol; $color):
    "\($text) | sfimage=\($symbol) sfcolor=\($color) color=\($color)";

  if .invalid > 0 then title(.sessions | length; "exclamationmark.triangle"; $c.warning)
  elif count("waiting") > 0 then title(count("waiting"); "exclamationmark.circle.fill"; $c.waiting)
  elif count("idle") > 0 then title(count("idle"); "checkmark.circle"; $c.idle)
  elif count("uncertain") > 0 then title(count("uncertain"); "questionmark.circle"; $c.uncertain)
  elif (.sessions | length) > 0 then title(.sessions | length; $icon; $c.busy)
  else title(""; $icon; $c.none)
  end
'

# render DATA — prints the SwiftBar menu for the loaded sessions.
render() {
  printf '%s' "$1" | "$JQ" -r --arg icon "$cfg_icon" --argjson c "$COLORS" "$HEADER_JQ"'
    , "---"
    , (if .invalid > 0 then "\(.invalid) state file(s) could not be read | color=gray" else empty end)
    , "\(.sessions | length) session(s)"
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
