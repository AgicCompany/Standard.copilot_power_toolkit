---
name: 'Project Context Check'
description: 'Raises a gate at session start when project-context.md is still the unfilled template, so the /setup mechanism does not depend on someone remembering it exists'
tags: ['context', 'session-start', 'setup']
---

# Project Context Check

`project-context.md` ships as a template. `/setup` fills it from what is actually in the repo. That
works — when someone runs it.

Across the entire 2026-08 acceptance run, in two separate projects and eleven steps, **nobody ever
did.** The prompt shipped in the `common` profile, sat in `.github/prompts/`, and was never invoked.
This hook is the surface that makes the mechanism self-starting rather than self-documenting.

## Why an unfilled template is worse than no file

It is not a neutral placeholder. Observed live 2026-08-02: an agent read it mid-task and concluded
*"I'm skipping the project context file since it's just a template and I can't verify the details."*
That is a step spent, on every task, routing around a file that is supposed to save steps. And an
unfilled form sitting next to real content is the worst state of all — later sessions cannot tell
which lines are facts.

## When it fires

Only when the file is **present and still contains placeholders** (`*e.g. …*`, or the template's own
"Fill this file after copying" header). It is silent when:

- the file does not exist — a project that never copied the template does not need telling every
  session
- the file has been filled — a real file has no `*e.g. …*` lines left

Matching on placeholders rather than on "does it look short" is what keeps it quiet once the job is
done.

## Why the wording is a gate

Measured A/B on this baseline's own hooks: advisory phrasing (*"offer to…"*, *"raise it once"*) was
read, deprioritised, and mentioned only when challenged. Gate phrasing (*"STOP — ACT ON THIS BEFORE
YOUR FIRST EDIT"*) produced compliance. **The escape hatch is what prevents nagging, not softer
language** — the message ends by telling the agent to accept "it's deliberate" and drop it for the
session.

The message also carries the rule that `/setup` itself learned the hard way: every line written into
that file must trace to a file that was actually read. A filled `project-context.md` is treated as
settled fact by every later session, so a plausible guess in it is worse than a blank.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `SKIP_PROJECT_CONTEXT_CHECK` | unset | `true` disables the hook entirely |
| `PROJECT_CONTEXT_FILE` | `.github/project-context.md` | path to check |

## Note for hook authors

`additionalContext` **must** be nested under `hookSpecificOutput` with a matching `hookEventName`. A
flat `{ "additionalContext": … }` is accepted, raises no error, and is silently discarded — five
hooks in this baseline carried that bug and had never worked in any project. See
`docs/reference/hook-payloads.md`.
