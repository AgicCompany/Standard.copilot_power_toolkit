---
name: 'Memory Reminder'
description: 'Prints a short reminder at session start pointing to docs/project-memory.md, so the memory mechanism does not depend on being remembered unprompted'
tags: ['memory', 'session-start']
---

# Memory Reminder

`instructions/memory.instructions.md` tells agents to read `docs/project-memory.md` before
non-trivial work. That instruction only helps if something actually surfaces it at the right
moment — this hook is that surface. It doesn't inject the file's contents (that's the agent's job,
reading it directly gives it real context instead of a truncated hook stdout blob); it just makes
sure "this file exists and has N entries" is visible at the start of every session.

## What It Does

At session start, checks `.github/docs/project-memory.md` (configurable via `MEMORY_FILE`):
- Doesn't exist → prints a note that there's no project memory yet.
- Exists but empty → prints a note that it's set up but unused.
- Exists with entries → prints the count, as a nudge to actually go read it.

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `SKIP_MEMORY_REMINDER` | unset | `true` disables the hook entirely |
| `MEMORY_FILE` | `.github/docs/project-memory.md` | Path to the memory file, relative to repo root |
