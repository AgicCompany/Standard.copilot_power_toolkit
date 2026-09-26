---
name: 'Memory Reminder'
description: 'Prints a short reminder at session start pointing to .github/docs/project-memory.md, so the memory mechanism does not depend on being remembered unprompted'
tags: ['memory', 'session-start']
---

# Memory Reminder

`instructions/memory.instructions.md` tells agents to read `.github/docs/project-memory.md` before
non-trivial work. That instruction only helps if something actually surfaces it at the right
moment — this hook is that surface. It doesn't inject the file's contents (that's the agent's job,
reading it directly gives it real context instead of a truncated hook stdout blob); it just makes
sure "this file exists and has N entries" is visible at the start of every session.

## What It Does

At session start, checks `.github/docs/project-memory.md` (configurable via `MEMORY_FILE`):
- Exists with at least one dated entry (`- YYYY-MM-DD: ...`) → tells Copilot how many entries there
  are, as a nudge to actually go read it.
- Doesn't exist, or has no dated entries → **silent**. That is deliberate: every `sessionStart` hook
  either emits one JSON object or nothing, and a reminder about an empty file is noise that trains
  people to ignore the real one. `tools/probe-hooks.sh` asserts the silence.

The bash mirror is also silent when `jq` is not installed.

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `SKIP_MEMORY_REMINDER` | unset | `true` disables the hook entirely |
| `MEMORY_FILE` | `.github/docs/project-memory.md` | Path to the memory file, relative to repo root |
