---
name: 'Dataverse Schema Drift'
description: 'Warns at session start when power.config.json is newer than the Power Apps CLI generated services, since stale generated code fails at runtime, not build time'
tags: ['dataverse', 'power-platform', 'session-start', 'codegen']
---

# Dataverse Schema Drift

## The problem this catches

Generated Dataverse services in `src/generated/` are produced by Power Apps CLI from the data sources in
`power.config.json`. To pick up a schema change you refresh the data source, or delete and
re-add the data source.

That makes drift silent and expensive:

- The generated TypeScript still compiles, because it describes the *old* schema.
- Types still check, because they're generated types — they agree with themselves.
- The failure appears at **runtime**, as a Dataverse error about a column that no longer exists or a
  new required field that was never sent.

Nothing in the normal build/typecheck loop can see this. `build-gate` will pass. That's precisely
why it needs to be a hook.

## What It Does

At session start, compares the last-modified time of `power.config.json` against the newest file in
`src/generated/`. If the config is newer, it emits `additionalContext` — the one stdout channel
`sessionStart` parses and injects into the session — telling Copilot that:

- generated services may not match the current data sources,
- regenerating is `pa app refresh data-source --name <name>`,
- it should not "fix" generated files by hand.

It also **speaks** when `power.config.json` exists but `src/generated/` does not — the typed
services were never generated, so it says to run `pa app add data-source` before writing data access
code.

Silent when the project has no `power.config.json` (not a Code App), when `src/generated/` exists but
is empty, when there is no drift, and — in the bash mirror — when `jq` is not installed.

## Why mtime and not a content hash

A content hash would require parsing `power.config.json`'s data-source list and reconciling it
against generated file names — more precise, but it fails closed in confusing ways when Power Apps CLI
changes its output layout. Mtime is coarse and can false-positive after an unrelated edit to the
config (or a fresh `git clone`, where checkout order decides mtimes). That trade is deliberate: this
hook prints an advisory line, it never blocks, so a false positive costs one sentence of context and
a false negative costs a runtime outage.

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `SKIP_SCHEMA_DRIFT` | unset | `true` disables the hook entirely |
| `POWER_CONFIG` | `power.config.json` | Path to the Power Apps config, relative to repo root |
| `GENERATED_DIR` | `src/generated` | Directory holding Power Apps CLI generated services/models |
