# Conformance suite

Language-neutral test cases for the snapshot engine: input files in, expected snapshot out. The Swift core runs
them in `tests/ASBCoreTests/ConformanceTests.swift`; any later implementation (for example a Rust core) must pass
the same cases. A case is data only, so behavior is pinned down independently of the code that implements it.

## A case

A case is either one file, `<name>.case.json` (most cases), or a directory (below). Both say the same things.

### Single-file cases

```json
{
  "description": "optional: what the case checks",
  "pending": "optional: why the behavior isn't implemented yet",
  "input": {
    "clock": {"now_ms": 1792891080000, "tz": "America/Los_Angeles"},
    "state": {"s1.json": {"v": 1, "sessionId": "s1", "state": "idle"}, "bad.json": "not json"},
    "registry": {"4242.json": {"pid": 4242, "sessionId": "s1", "status": "idle", "statusUpdatedAt": 1792891020000}},
    "transcripts": {"t.jsonl": {"fixture": "denied-permission", "lines": [{"type": "user"}], "repeat": {"line": {}, "times": 30}, "mtime": 0}},
    "processes": [{"pid": 4242, "ppid": 1, "start": 1792426323, "comm": "claude"}],
    "herdr": {"result": {"agents": []}},
    "config": "stale_minutes=0\n",
    "mutes": {"/x/proj": {"until": 1792894680000, "at": 1792891080000, "today": false}}
  },
  "expected": {"version": 1, "...": "the snapshot"},
  "expectedDead": ["state/s1.json"]
}
```

- Only `input.clock` and `expected` are required.
- File contents (`state`, `registry`, `herdr`, `mutes`) are written as JSON; a string is used as the raw contents
  instead, to give corrupt files.
- A transcript is built from a fixture in `tests/fixtures/transcripts/` (optional), then `lines`, then
  `repeat.times` copies of `repeat.line`, each line followed by a newline.

### Directory cases

One directory per case, named after what it checks (`c1-dead`, `mute-today`, ...):

```
<case>/
├── input/
│   ├── clock.json          required: {"now_ms": 1792891080000, "tz": "America/Los_Angeles"}
│   ├── state/*.json        session state files (doc/state-file-schema.md), any names
│   ├── registry/*.json     Claude Code registry files (~/.claude/sessions/<pid>.json)
│   ├── transcripts/*       transcript files
│   ├── transcripts.json    optional: {"<file name>": <mtime epoch ms>}; default mtime 0
│   ├── processes.json      optional: [{"pid": 4242, "ppid": 1, "start": 1792890000, "comm": "claude", "args": "claude"}]
│   ├── herdr.json          optional: raw `herdr agent list` output; its presence means herdr is installed
│   ├── config              optional: the config file (key=value)
│   └── mutes               optional: the mutes file
├── expected.json           the snapshot (doc/snapshot-schema.md)
├── expected-dead.json      optional: state files the engine reports dead, e.g. ["state/s1.json"]; default []
└── pending                 optional: the case documents behavior not implemented yet (contents: why)
```

Paths:

- State and registry files are passed to the engine as `state/<name>` and `registry/<name>`, so dead files are
  reported in that form.
- A state file refers to a transcript as `"transcriptPath": "transcripts/<name>"`; the runner passes each
  transcript under exactly that key.

Time: `clock.json` fixes `now` (epoch ms) and the time zone, so durations and mute times are deterministic.
`generatedAt` in `expected.json` equals `now_ms`.

## Comparing

The runner decodes `expected.json` and the engine's snapshot as JSON and compares them as values (key order and
formatting don't matter, absent and `null` are different). On a mismatch it prints both, pretty-printed with sorted
keys, and the lines that differ.

## Pending cases

A case with a `pending` file runs as a known issue: its failure is reported but doesn't fail the suite. When the
case starts passing, the suite fails until the `pending` file is removed, so a pending case can't be forgotten.
Nothing else is ever skipped.

## Adding a case

1. Create the directory and the input files.
2. Write `expected.json` by hand from the rules in the PRD and the schema docs (not by copying the engine's output).
3. Run `tests/swift.sh --filter Conformance`.
