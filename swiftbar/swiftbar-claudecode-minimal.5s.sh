#!/bin/sh
# shellcheck source-path=SCRIPTDIR disable=SC2016
# (SC2016: jq programs use $variables inside single quotes on purpose.)
#
# <xbar.title>Minimalist Claude Code Statusbar</xbar.title>
# <xbar.version>v1.0.0-rc.1</xbar.version>
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
#
# A refresh gathers raw inputs with a handful of processes (awk, stat, tail, ps)
# and does all parsing, checks and rendering in one jq program.

# Highest state file version this plugin understands.
MAX_STATE_VERSION=1

# Resolve our own path, following symlinks (SwiftBar runs a symlink).
self="$0"
while [ -L "$self" ]; do
  link="$(readlink "$self")"
  case "$link" in
    /*) self="$link" ;;
    *) self="${self%/*}/$link" ;;
  esac
done
case "$self" in
  /*) plugin_path="$self" ;;
  *) plugin_path="$PWD/$self" ;;
esac
plugin_dir="${plugin_path%/*}"
# shellcheck source=../lib/common.sh
. "$plugin_dir/../lib/common.sh" || exit 1

# join_files FILE... — one "path<TAB>content" line per file (newlines in a file
# are dropped), so a file without a trailing newline can't run into the next one.
join_files() {
  [ -e "$1" ] || return 0
  awk 'FNR == 1 { if (NR > 1) print ""; printf "%s\t", FILENAME } { printf "%s", $0 } END { if (NR > 0) print "" }' "$@" 2>/dev/null
}

# Bytes of each transcript the interrupt check reads.
TRANSCRIPT_TAIL_BYTES=8192
# Text Claude Code writes to the transcript when a turn is interrupted or a
# permission is denied (see tests/fixtures/README.md).
INTERRUPT_MARKER='[Request interrupted by user'

# read_transcripts PATH... — for each transcript: "M<TAB>path<TAB>mtime" and one
# "T<TAB>path<TAB>entry" per line of its last TRANSCRIPT_TAIL_BYTES. The first line
# of a cut tail is dropped. One stat and one tail for all files.
read_transcripts() {
  [ "$#" -gt 0 ] || return 0
  {
    stat -f 'S %m %z %N' -- "$@" 2>/dev/null
    # /dev/null makes tail print a header for every file, even a single one.
    tail -c "$TRANSCRIPT_TAIL_BYTES" -- "$@" /dev/null 2>/dev/null
  } | awk -v max="$TRANSCRIPT_TAIL_BYTES" '
    !inblocks && /^S [0-9]+ [0-9]+ / {
      p = $0; sub(/^S [0-9]+ [0-9]+ /, "", p)
      size[p] = $3; print "M\t" p "\t" $2; next
    }
    /^==> .* <==$/ { inblocks = 1; cur = substr($0, 5, length($0) - 8); drop = (size[cur] + 0 > max); next }
    cur == "" || cur == "/dev/null" || length($0) == 0 { next }
    drop { drop = 0; next }
    { print "T\t" cur "\t" $0 }
  '
}

# Seconds `herdr agent list` may take before titles are skipped for this refresh.
HERDR_LIST_TIMEOUT=1

# Menu-bar colors as light,dark pairs.
COLORS='{
  "waiting": "#D70015,#FF453A",
  "idle": "#B25000,#FFD60A",
  "uncertain": "#8E8E93,#98989D",
  "busy": "#6E6E73,#AEAEB2",
  "none": "#C7C7CC,#48484A",
  "muted": "#8E8E93,#98989D",
  "warning": "#B25000,#FFD60A"
}'

# Muted projects, in the state dir: {cwd: {until, at, today}} with epoch ms.
# Not a .json file, so it is never read as a session.
MUTES_FILE=mutes

# Width of the row label (project — title) before the state column.
LABEL_WIDTH=48

# Parsing the raw inputs.
PARSE_JQ='
  def raw_lines: split("\n") | map(select(length > 0));

  # {"sessions": [...], "invalid": N}. Files that do not parse, are not objects
  # or have an unknown version count as invalid.
  def parse_sessions:
    raw_lines
    | map(index("\t") as $i | {file: .[0:$i], s: (.[$i + 1:] | try fromjson catch null)})
    | map(.ok = ((.s | type) == "object" and ((.s.v // 0) | type) == "number"
                 and .s.v >= 1 and .s.v <= $maxv))
    | {sessions: [.[] | select(.ok) | .s + {file: .file}],
       invalid: ([.[] | select(.ok | not)] | length)};

  # Claude Code'"'"'s session registry as {pid: entry}.
  def parse_registry:
    raw_lines
    | map(index("\t") as $i | .[$i + 1:] | try fromjson catch null | select(type == "object" and .pid != null))
    | map({key: (.pid | tostring), value: .}) | from_entries;

  # {tails: {path: [entries]}, mtimes: {path: ms}} from read_transcripts.
  def parse_transcripts:
    reduce (raw_lines[] | split("\t")) as $p ({tails: {}, mtimes: {}};
      if $p[0] == "M" then .mtimes[$p[1]] = (($p[2] | tonumber) * 1000)
      elif $p[0] == "T" then
        ($p[2:] | join("\t") | try fromjson catch null) as $e
        | if $e == null then . else .tails[$p[1]] += [$e] end
      else . end);

  # {claude session ID: terminal title} from `herdr agent list`.
  def parse_titles:
    try (fromjson
         | [.result.agents[]? | select(.agent == "claude" and (.agent_session.value // "") != "")
            | {key: .agent_session.value, value: (.terminal_title_stripped // "")}]
         | from_entries)
    catch {};

  def norm: gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ");

  # pid -> {ppid, lstart, comm} from `ps -axo pid=,ppid=,lstart=,comm=`
  def procs:
    split("\n")
    | map(select(test("\\S")) | sub("^\\s+"; "") | [splits("\\s+")])
    | map({key: .[0], value: {ppid: .[1], lstart: (.[2:7] | join(" ")), comm: (.[7:] | join(" "))}})
    | from_entries;

  # A local-time lstart ("Mon Oct 19 09:12:03 2026") as epoch milliseconds.
  def lstart_ms: (norm | strptime("%a %b %d %H:%M:%S %Y") | mktime - $tzoffset) * 1000;
'

# The checks, in order. Each session gets a display state (`shown`); dead ones
# are listed and dropped. Checks never write state files.
CHECKS_JQ='
  # C1: the claude process must still exist and have the same start time.
  def alive:
    if .pid == null then true
    else $P[.pid | tostring] as $p
      | $p != null and (.procStart == null or ($p.lstart | norm) == (.procStart | norm))
    end;

  # C2: Claude Code'"'"'s own registry wins when it is newer than our state file.
  def registry:
    (if .pid == null then null else $reg[.pid | tostring] end) as $r
    | if $r == null or $r.sessionId != .sessionId then .
      else
        # A name the user gave the session (not one Claude Code derived).
        (if ($r.name // "") != "" and $r.nameSource != "derived" then .sessionName = $r.name else . end)
      end
    | if $r == null or $r.sessionId != .sessionId then .
      elif ($r.status | type) != "string" then .registrySchema = false
      elif ($r.statusUpdatedAt // 0) <= (.updatedAt // 0) then .
      elif $r.status == "busy" then .shown = "busy" | .shownSince = $r.statusUpdatedAt
      elif $r.status == "idle" then .shown = "idle" | .shownSince = $r.statusUpdatedAt
      elif $r.status == "waiting" then
        .shown = "waiting" | .shownSince = $r.statusUpdatedAt
        | .reason = (if ($r.waitingFor // "" | test("permission")) then "permission" else "question" end)
      else . end;

  # A prompt the user (or a background task) sent; not a tool result, meta
  # entry or interrupt marker.
  def prompt_text:
    .message.content
    | if type == "string" then .
      elif type == "array" then (map(select(.type == "text") | .text) | join(" "))
      else "" end;
  def is_prompt:
    .type == "user" and (.isMeta != true)
    and ((.message.content | type) == "string"
         or any(.message.content[]?; .type == "text"))
    and (prompt_text | startswith($marker) | not);
  def ends_turn:
    (.type == "system" and .subtype == "turn_duration")
    or (.type == "user" and (prompt_text | startswith($marker)));

  # C3: busy or waiting, but the transcript shows the turn already ended.
  def interrupted($entries):
    ($entries | [to_entries[] | select(.value | is_prompt) | .key] | last) as $p
    | ($entries | if $p == null then . else .[$p + 1:] end)
    | any(.[]; ends_turn);

  # C4: waiting, but a tool process started after the prompt: it was approved.
  # caffeinate is started by Claude Code at the beginning of every turn.
  def approved_since:
    (.pid | tostring) as $pid | (.shownSince // .stateSince // 0) as $since
    | [$P | to_entries[] | .value
       | select(.ppid == $pid and (.comm | split("/") | last) != "caffeinate")
       | (.lstart | lstart_ms) | select(. > $since)]
    | min;

  # C5: the latest sign of life: a hook write, a transcript write, a new child process.
  def last_activity:
    (.pid | tostring) as $pid
    | [(.updatedAt // 0), (.shownSince // 0), ($mtimes[.transcriptPath // ""] // 0)]
      + [$P | to_entries[] | .value | select(.ppid == $pid) | .lstart | lstart_ms]
    | max;

  .sessions |= map(.shown = .state | .alive = alive)
  | .dead = [.sessions[] | select(.alive | not) | .file]
  | .sessions |= map(select(.alive) | del(.alive) | registry
      | ($tails[.transcriptPath // ""]) as $entries
      | if (.shown == "busy" or .shown == "waiting") and $entries != null and interrupted($entries)
        then .shown = "idle" | .shownSince = .updatedAt
        else . end
      | if .shown == "waiting" and .pid != null then
          approved_since as $t
          | if $t != null then .shown = "busy" | .shownSince = $t else . end
        else . end
      | if .shown == "busy" and $stale > 0 then
          last_activity as $t
          | if ($now - $t) > ($stale * 60000) then .shown = "uncertain" | .shownSince = $t else . end
        else . end)
  | .registrySchemaIssue = any(.sessions[]; .registrySchema == false)
'

# Hidden session kinds are left out of the rows and the menu-bar count.
FILTERS_JQ='
  # (Not `// true`: jq treats false as missing there.)
  def shown_kind($kind):
    {interactive: $f.interactive, headless: $f.headless, ide: $f.ide, desktop: $f.ide}[$kind]
    | if . == null then true else . end;
  .sessions |= map(select(shown_kind(.kind // "interactive")))
'

# Muted projects: a session whose project (cwd) has a mute that hasn't expired,
# and hasn't been lifted by a prompt sent after it, gets `muteUntil`. Unless it
# is waiting on the user, it is `muted`: out of the menu-bar count, last in the list.
MUTES_JQ='
  ([.sessions[] | select(.cwd != null and .promptAt != null) | {key: .cwd, value: .promptAt}]
   | group_by(.key) | map({key: .[0].key, value: (map(.value) | max)}) | from_entries) as $prompted
  | ($mutes | with_entries(select((.value.until // 0) > $now
      and ((.value.at // 0) >= ($prompted[.key] // 0))))) as $active
  | .activeMutes = ($active | length)
  | .sessions |= map(
      $active[.cwd // ""] as $m
      | if $m == null then .
        else .muteUntil = $m.until | .muteToday = ($m.today == true) | .muted = (.shown != "waiting") end)
'

# The menu-bar line: the most urgent state (waiting > idle > uncertain > busy)
# and the number of sessions in it. Each state has its own symbol, so color is
# never the only signal. Muted sessions don't count; when all are muted, a
# muted icon shows instead.
#
# Symbols are written inline (":zzz:"), not as sfimage: SwiftBar applies
# sfcolor, with its light,dark pair, only to inline symbols and draws an
# sfimage in the plain menu-bar color.
HEADER_JQ='
  [.sessions[] | select(.muted != true)] as $loud
  | def count($st): [$loud[] | select(.shown == $st)] | length;
  def title($text; $symbol; $color):
    ":\($symbol):\(if $text == "" then "" else " \($text)" end) | sfcolor=\($color) color=\($color)";

  if .invalid > 0 then title(.sessions | length; "exclamationmark.triangle"; $c.warning)
  elif count("waiting") > 0 then title(count("waiting"); "exclamationmark.circle.fill"; $c.waiting)
  elif count("idle") > 0 then title(count("idle"); "zzz"; $c.idle)
  elif count("uncertain") > 0 then title(count("uncertain"); "questionmark.circle"; $c.uncertain)
  elif ($loud | length) > 0 then title($loud | length; $icon; $c.busy)
  elif (.sessions | length) > 0 then title(""; "bell.slash"; $c.muted)
  else title(""; $icon; $c.none)
  end
'

# One row per session, most urgent first; within a state, longest in it first.
ROWS_JQ='
  def rank: if .muted then 5 else {waiting: 0, idle: 1, uncertain: 2, busy: 3}[.shown] // 4 end;
  # The same symbol and color the menu bar uses for this state: [symbol, color].
  def state_icon:
    if .muted then ["bell.slash", $c.muted] else
      {waiting: ["exclamationmark.circle.fill", $c.waiting], idle: ["zzz", $c.idle],
       uncertain: ["questionmark.circle", $c.uncertain]}[.shown] // [$icon, $c.busy] end;
  def word:
    if .shown == "waiting" then (if .reason == "question" then "question" else "permission" end)
    elif .shown == "idle" then "idle"
    elif .shown == "uncertain" then "no activity"
    else "working" end;
  def since: .shownSince // .stateSince // $now;
  def mute_text:
    if .muteToday then "muted today"
    else "muted until \(.muteUntil / 1000 | floor | localtime | strftime("%H:%M"))" end;
  # Time since $t (epoch ms) as 12s, 4m, 2h or 3d.
  def ago($t): (($now - $t) / 1000 | floor | if . < 0 then 0 else . end) as $s
    | if $s < 60 then "\($s)s" elif $s < 3600 then "\($s / 60 | floor)m"
      elif $s < 86400 then "\($s / 3600 | floor)h" else "\($s / 86400 | floor)d" end;
  def duration: ago(since);
  # Title source, best first: herdr terminal title, a user-given session name,
  # the first prompt.
  def nonempty: select(. != null and . != "");
  def row_title: [($titles[.sessionId] | nonempty), (.sessionName | nonempty), (.promptPreview | nonempty), ""] | first;
  def project: (.cwd // "") | split("/") | map(select(. != "")) | last // "unknown";
  def fit: gsub("\\|"; "│")
    | if length > $width then .[0:$width - 1] + "…" else . + (" " * ($width - length)) end;
  # A zero-width space keeps ":name:" in a title from becoming an inline symbol.
  def no_symbols: gsub(":(?<w>[A-Za-z0-9._-]+):"; ":​\(.w):");
  def row_label: (project + (row_title as $t | if $t == "" then "" else " — " + $t end)) | fit | no_symbols;

  # Subagents: indented under their parent, informational only.
  def subagent_rows:
    if $f.subagents then
      (.subagents // {}) | to_entries | sort_by(.value.since) | .[]
      | "  \("↳ subagent: \(.value.type)" | fit)  working · \(ago(.value.since // $now)) | font=Menlo size=12 color=gray"
    else empty end;

  # A submenu item that runs this plugin with an action and the session ID.
  def action($text; $name):
    "--\($text) | bash=\"\($plugin)\" param1=\($name) param2=\(.sessionId) terminal=false";

  # Rows focus their session on click when it runs in a herdr pane (v1: herdr only).
  def can_focus: $herdr and (.herdrPane // "") != "";
  def click:
    if can_focus then " bash=\"\($plugin)\" param1=focus param2=\(.sessionId) terminal=false" else "" end;

  .sessions
  | sort_by(rank, since)
  | .[]
  | state_icon as [$symbol, $color]
  | ":\($symbol): \(row_label)  \(word) · \(if .muted then mute_text else duration end) | font=Menlo size=12 sfcolor=\($color)\(click)",
    (if can_focus then empty else "--Not in herdr: click to focus is unavailable | color=gray" end),
    (if .cwd == null then empty
     elif .muteUntil then action("Unmute project"; "unmute") + " refresh=true"
     else action("Mute project for 1 hour"; "mute-hour") + " refresh=true",
          action("Mute project for today"; "mute-today") + " refresh=true" end),
    action("Copy session ID"; "copy-id"),
    action("Copy working directory"; "copy-cwd"),
    (if .cwd then action("Open folder in Finder"; "open-folder") else empty end),
    (if .transcriptPath then action("Reveal transcript"; "reveal-transcript") else empty end),
    subagent_rows
'

# The Show section and the Settings submenu.
FOOTER_JQ='
  def toggle($text; $key):
    "\($text) | bash=\"\($plugin)\" param1=toggle param2=\($key) terminal=false refresh=true"
    + (if $f[$key | ltrimstr("show_")] then " checked=true" else "" end);
  def run($args): " | bash=\"\($plugin)\" \($args) terminal=false refresh=true";
  def check($on): if $on then " checked=true" else "" end;
  def setting_toggle($text; $key):
    "--\($text)" + run("param1=toggle param2=\($key)") + check($s[$key] == 1);
  def stale_option($text; $minutes):
    "----\($text)" + run("param1=set param2=stale_minutes param3=\($minutes)") + check($s.stale_minutes == $minutes);

  (if .activeMutes > 0 then "Unmute all projects" + run("param1=unmute-all") else empty end),
  "Show | color=gray",
  toggle("Interactive"; "show_interactive"),
  toggle("Headless (claude -p)"; "show_headless"),
  toggle("Subagents"; "show_subagents"),
  toggle("IDE / Desktop"; "show_ide"),
  "Settings…",
  "--Mark busy sessions as uncertain after",
  stale_option("10 minutes"; 10),
  stale_option("30 minutes"; 30),
  stale_option("60 minutes"; 60),
  stale_option("Never"; 0),
  setting_toggle("Refresh instantly on changes"; "instant_refresh"),
  setting_toggle("Use Claude Code session registry"; "use_registry"),
  setting_toggle("Store prompt previews"; "store_prompt_preview"),
  "--Reveal config file" + run("param1=reveal-config")
'

# The whole refresh: parse, check, then print side-effect lines (##dead, ##schema)
# for the shell, followed by the menu.
REFRESH_JQ='
  (now * 1000 | floor) as $now
  | ((now | floor) as $n | ($n | localtime | mktime) - $n) as $tzoffset
  | '"$PARSE_JQ"'
  ($ps | procs) as $P
  | ($registry | parse_registry) as $reg
  | ($transcripts | parse_transcripts) as $T
  | $T.tails as $tails
  | $T.mtimes as $mtimes
  | ($herdrList | parse_titles) as $titles
  | ($mutesRaw | try fromjson catch {} | if type == "object" then . else {} end) as $mutes
  | ($sessions | parse_sessions)
  | ('"$CHECKS_JQ"')
  | ((.dead[] | "##dead\t\(.)"),
     (if .registrySchemaIssue then "##schema" else empty end),
     ('"$FILTERS_JQ"' | '"$MUTES_JQ"'
      | ('"$HEADER_JQ"'),
        "---",
        (if .invalid > 0 then "\(.invalid) state file(s) could not be read | color=gray" else empty end),
        (if (.sessions | length) == 0 then "No Claude Code sessions | color=gray" else empty end),
        ('"$ROWS_JQ"'),
        "---",
        ('"$FOOTER_JQ"'),
        "---",
        "Refresh | refresh=true"))
'

render_jq_missing() {
  echo "⚠︎ | sfimage=exclamationmark.triangle"
  echo "---"
  echo "Minimalist Claude Code Statusbar needs jq"
  echo "Install it with: brew install jq | color=gray"
}

# bool VALUE — "true" for 1, else "false".
bool() {
  if [ "$1" = 1 ]; then echo true; else echo false; fi
}

refresh() {
  set -- "$cfg_state_dir"/*.json
  _sessions="$(join_files "$@")"

  # Transcripts of busy or waiting sessions (for C3 and C5).
  _paths="$(printf '%s' "$_sessions" | "$JQ" -r -R '
    index("\t") as $i | .[$i + 1:] | try fromjson catch null
    | select(type == "object" and (.state == "busy" or .state == "waiting")
             and (.transcriptPath | type) == "string" and .transcriptPath != "")
    | .transcriptPath
  ' 2>/dev/null)"
  _transcripts=""
  if [ -n "$_paths" ]; then
    _ifs="$IFS"
    IFS='
'
    set -f
    # shellcheck disable=SC2086 # one path per line
    set -- $_paths
    set +f
    IFS="$_ifs"
    _transcripts="$(read_transcripts "$@")"
  fi

  _registry=""
  if [ "$cfg_use_registry" = 1 ]; then
    set -- "${CLAUDE_STATUSBAR_REGISTRY_DIR:-$HOME/.claude/sessions}"/*.json
    _registry="$(join_files "$@")"
  fi

  _ps="$(ps -axo pid=,ppid=,lstart=,comm= 2>/dev/null)"

  # herdr's output goes to a file: if herdr hangs and is killed, a child it left
  # behind could keep a $(...) pipe open and stall the refresh.
  _herdr="$(find_herdr)"
  _herdr_file=/dev/null
  if [ -n "$_herdr" ] && _herdr_file="$(mktemp "${TMPDIR:-/tmp}/swiftbar-claudecode-minimal-herdr.XXXXXX")"; then
    trap 'rm -f "$_herdr_file"' EXIT
    run_with_timeout "$HERDR_LIST_TIMEOUT" "$_herdr" agent list > "$_herdr_file" 2>/dev/null
  fi

  _mutes_file="$cfg_state_dir/$MUTES_FILE"
  [ -f "$_mutes_file" ] || _mutes_file=/dev/null

  "$JQ" -n -r \
    --arg sessions "$_sessions" --arg transcripts "$_transcripts" --rawfile mutesRaw "$_mutes_file" \
    --arg registry "$_registry" --arg ps "$_ps" --rawfile herdrList "$_herdr_file" \
    --argjson maxv "$MAX_STATE_VERSION" --arg marker "$INTERRUPT_MARKER" \
    --argjson stale "$cfg_stale_minutes" \
    --argjson f "$(printf '{"interactive":%s,"headless":%s,"subagents":%s,"ide":%s}' \
      "$(bool "$cfg_show_interactive")" "$(bool "$cfg_show_headless")" \
      "$(bool "$cfg_show_subagents")" "$(bool "$cfg_show_ide")")" \
    --argjson s "$(printf '{"stale_minutes":%s,"instant_refresh":%s,"use_registry":%s,"store_prompt_preview":%s}' \
      "$cfg_stale_minutes" "$cfg_instant_refresh" "$cfg_use_registry" "$cfg_store_prompt_preview")" \
    --arg icon "$cfg_icon" --argjson c "$COLORS" --argjson width "$LABEL_WIDTH" \
    --arg plugin "$plugin_path" --argjson herdr "$([ -n "$_herdr" ] && echo true || echo false)" \
    "$REFRESH_JQ" |
    while IFS= read -r _line; do
      case "$_line" in
        "##dead	"*)
          _f="${_line#*	}"
          case "$_f" in
            "$cfg_state_dir"/*.json) rm -f "$_f" ;;
          esac
          ;;
        "##schema")
          log_once registry-schema "Claude Code session registry has no 'status' field; registry override disabled for those sessions."
          ;;
        *) printf '%s\n' "$_line" ;;
      esac
    done
}

# session_field ID FILTER — prints a field from a session's state file.
session_field() {
  case "$1" in
    '' | *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  "$JQ" -r "$2 // empty" "$cfg_state_dir/$1.json" 2>/dev/null
}

# Seconds each focus step may take before it is abandoned.
FOCUS_TIMEOUT=2

# focus_session SESSION_ID — brings the session's herdr pane to front. The one
# place to add other integrations later. Fails safe: on any error nothing else
# happens; it never launches apps or opens windows.
focus_session() {
  _pane="$(session_field "$1" '.herdrPane')"
  case "$_pane" in
    '' | *[!A-Za-z0-9:_-]*) return 0 ;;
  esac
  _herdr="$(find_herdr)"
  [ -n "$_herdr" ] || return 0
  run_with_timeout "$FOCUS_TIMEOUT" "$_herdr" agent focus "$_pane" >/dev/null 2>&1 || return 0

  # Raise the terminal hosting herdr.
  _bundle="$(session_field "$1" '.termBundleId')"
  case "$_bundle" in
    '' | *[!A-Za-z0-9.-]*) return 0 ;;
  esac
  run_with_timeout "$FOCUS_TIMEOUT" open -b "$_bundle" >/dev/null 2>&1
  return 0
}

# update_mutes FILTER [JQ ARGS] — rewrites the mutes file through FILTER, which
# can use $now and $midnight (next local midnight), both epoch ms. Expired
# mutes and an unreadable file are dropped.
update_mutes() {
  _filter="$1"
  shift
  _mutes="$cfg_state_dir/$MUTES_FILE"
  _old=/dev/null
  [ -f "$_mutes" ] && _old="$_mutes"
  mkdir -p "$cfg_state_dir" || return 0
  "$JQ" -c -R -s "$@" '
    (now * 1000 | floor) as $now
    | ((now | floor) as $n | ($n | localtime | mktime) - $n) as $tzoffset
    | (now | floor | localtime | .[2] += 1 | .[3] = 0 | .[4] = 0 | .[5] = 0
       | (mktime - $tzoffset) * 1000) as $midnight
    | (try fromjson catch {}) | (if type == "object" then . else {} end)
    | '"$_filter"'
    | with_entries(select((.value.until // 0) > $now))
  ' "$_old" 2>/dev/null | atomic_write "$_mutes"
}

# mute_project SESSION_ID FILTER [JQ ARGS] — update_mutes for the session's cwd as $cwd.
mute_project() {
  _cwd="$(session_field "$1" '.cwd')"
  [ -n "$_cwd" ] || return 0
  _filter="$2"
  shift 2
  update_mutes "$_filter" --arg cwd "$_cwd" "$@"
}

# write_default_config — a config file with every key at its current value.
write_default_config() {
  cat <<EOF
# Minimalist Claude Code Statusbar settings (key=value). The SwiftBar menu edits this file too.
show_interactive=$cfg_show_interactive
show_headless=$cfg_show_headless
show_subagents=$cfg_show_subagents
show_ide=$cfg_show_ide
stale_minutes=$cfg_stale_minutes
use_registry=$cfg_use_registry
instant_refresh=$cfg_instant_refresh
icon=$cfg_icon
store_prompt_preview=$cfg_store_prompt_preview
EOF
}

# run_action ACTION SESSION_ID — a menu action.
run_action() {
  case "$1" in
    focus)
      focus_session "$2"
      ;;
    toggle)
      case "$2" in
        show_interactive) _value="$cfg_show_interactive" ;;
        show_headless) _value="$cfg_show_headless" ;;
        show_subagents) _value="$cfg_show_subagents" ;;
        show_ide) _value="$cfg_show_ide" ;;
        instant_refresh) _value="$cfg_instant_refresh" ;;
        use_registry) _value="$cfg_use_registry" ;;
        store_prompt_preview) _value="$cfg_store_prompt_preview" ;;
        *) return 0 ;;
      esac
      if [ "$_value" = 1 ]; then set_config "$2" 0; else set_config "$2" 1; fi
      ;;
    set)
      # Only the stale threshold is set to a value, and only to the menu's choices.
      case "$2=$3" in
        stale_minutes=0 | stale_minutes=10 | stale_minutes=30 | stale_minutes=60)
          set_config "$2" "$3"
          ;;
      esac
      ;;
    reveal-config)
      _config="$(ca_config_file)"
      if [ ! -e "$_config" ]; then
        mkdir -p "$(dirname "$_config")"
        write_default_config > "$_config"
      fi
      open -R "$_config"
      ;;
    mute-hour)
      mute_project "$2" '.[$cwd] = {until: ($now + 3600000), at: $now, today: false}'
      ;;
    mute-today)
      mute_project "$2" '.[$cwd] = {until: $midnight, at: $now, today: true}'
      ;;
    unmute)
      mute_project "$2" 'del(.[$cwd])'
      ;;
    unmute-all)
      update_mutes '{}'
      ;;
    copy-id)
      session_field "$2" '.sessionId' | tr -d '\n' | pbcopy
      ;;
    copy-cwd)
      session_field "$2" '.cwd' | tr -d '\n' | pbcopy
      ;;
    open-folder)
      _dir="$(session_field "$2" '.cwd')"
      [ -d "$_dir" ] && open "$_dir"
      ;;
    reveal-transcript)
      _transcript="$(session_field "$2" '.transcriptPath')"
      [ -e "$_transcript" ] && open -R "$_transcript"
      ;;
  esac
  return 0
}

main() {
  load_config
  JQ="$(find_jq)"
  if [ -z "$JQ" ]; then
    render_jq_missing
    return 0
  fi

  if [ "$#" -gt 0 ]; then
    run_action "$@"
    return 0
  fi

  refresh
}

main "$@"
