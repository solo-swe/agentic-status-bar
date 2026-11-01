# The hook and the state files

`asb hook` runs on every Claude Code hook event of every session on the machine: every prompt and every tool call.
It turns the event into the session's state file (`doc/state-file-schema.md`), which the app reads. The hooks run the
stable copy of `asb` in `~/Library/Application Support/agentic-status-bar/bin/`, which the app keeps current.

## Never in Claude Code's way

- **Silent and always exit 0.** No output, no error codes: a failing hook must never show up in a session. Bad input
  is dropped.
- **Fast.** The hooks are async, but they run on every tool call: `asb hook` stays under 10 ms (`tests/bench.sh`). Do
  only what the event needs; expensive lookups, like the process table, happen only when a field is missing
  (`HookMetadata.needsBackfill`).
- **Safe names.** The session ID becomes a file name only after `Actions.isSafeId`.

## Writing

- **One writer at a time per session**: `StateWriter.withLock` (a lock directory; `mkdir` is atomic), then
  `StateWriter.atomicWrite` (temp file, then rename), so readers never see half a file.
- **Newer wins.** Async hooks finish out of order: an event that started before the last applied one (`eventAt`) is
  dropped, except subagent start and stop, which only add or remove their own entry.
- **Keep unknown fields.** A newer version may have written fields this one doesn't know.
- **Events are pure functions.** `HookEvents.apply(payload, to: state, …)` returns the new state; the hook does the
  I/O around it. Behaviour is tested there, event by event, in the orders Claude Code really sends.

## Changing the format

- **Additive only within version 1.** New fields are optional, and readers that don't know them must still work.
  Bumping `v` is a breaking change and needs its own decision.
- **Document it in the same commit**: the field table, the Events table and the rules in
  `doc/state-file-schema.md`; `doc/snapshot-schema.md` if the snapshot changes.
- **Pin it with tests**: `HookEventsTests` for the hook, conformance cases for what the engine shows.

## Learning what Claude Code sends

- Don't guess payload fields or event order. Capture them: `debug_hook_log=1` in the config makes `asb hook` append
  every payload to `<state dir>/hook-payloads.jsonl`. Turn it off and delete the file afterwards; it holds real
  prompts and paths.
- Sanitized copies go to `tests/fixtures/payloads/` (made-up IDs, paths and prompts), and the findings to
  `tests/fixtures/README.md`, with the Claude Code version and date.
- A new event the hook should handle goes into `HookSettings.events`; the app adds it to existing installs at
  launch (`Installer.hooksOutdated`). Behaviour must not depend on it being there: older installs lack it.
