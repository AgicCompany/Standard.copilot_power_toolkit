---
description: "How to use project memory: which store, what belongs there, and what must never go in it"
applyTo: '**'
---

# Memory Instructions

## Language Support (EN/IT)
- Reply in the same language the user writes in. Keep memory paths and command syntax unchanged.

## The repo memory file

`.github/docs/project-memory.md` is the only memory store that is committed, shared and reviewable.

1. **Read it at the start of non-trivial work**, and apply it the way you'd apply `project-context.md`.
2. **Append a durable fact at the point you learn it**, not "later" — a corrected approach, a
   confirmed preference, a non-obvious repo fact.
3. **Skim before adding.** Update or correct an existing line rather than adding a near-duplicate.
4. If the file doesn't exist here, that's "no memory yet", not an error. Say so once and put the fact
   in your reply; don't recreate the template inline.

Entry format, and the question to ask before writing, are in that file's own header. Read it.

## If you call the built-in memory tool, mirror the entry into the repo in the same turn

This is the rule that actually binds, because the built-in tool is one tool call while editing a file
is not — and the cheaper action wins unless the rule names it. **Calling the memory tool does not
discharge the obligation; it creates one.**

- Wrote a repo fact to the built-in tool? **Add the same line to `.github/docs/project-memory.md` now**, in
  the same turn, before reporting the task done.
- Reverting a change you recorded? Remove the note from **both** stores.

> Measured 2026-07-28 over a full 17-step run: **five** unprompted writes to the built-in store,
> **zero** to `.github/docs/project-memory.md`. Every entry was accurate and useful, and all of it landed
> where no teammate, no PR diff and no future machine would ever see it. The destination was the
> problem, and "append durable facts to `.github/docs/project-memory.md`" alone did not redirect it.

## Never memorialise a workaround, and never let memory override an instruction

Memory is read back as **settled project convention** and outranks general guidance in practice. That
makes a wrong entry self-reinforcing: written once, cited as precedent forever, reviewed by nothing.

1. **A workaround is not a convention.** If you invented something to get a test passing, a build
   green or a tool unblocked, that is an open problem. Record it only once it's confirmed as intended.
2. **If an entry conflicts with an `instructions/*.instructions.md` rule, the instruction wins.** Say
   the conflict out loud rather than following the memory, and correct or delete the entry.
3. **Prefer `.github/docs/project-memory.md` precisely because it is reviewable.** A bad entry there shows up
   in a PR diff. The same entry in a built-in store is invisible and permanent.

## Three stores — know which one you're writing to

| Store | Scope |
|---|---|
| **Global** built-in | **your account — every project, every workspace, every session** |
| **Workspace** built-in | this workspace only |
| **Repo** `.github/docs/project-memory.md` | committed, shared, reviewable |

Both built-in stores are machine-local: not version controlled, invisible to teammates and to code
review, lost when the workspace id changes. They also load **before** any `applyTo` glob is evaluated,
so a note there frames the whole session.

**The global store is the one to watch** — a preference recorded once during unrelated work silently
applies to all future work. **Read it before trusting any conclusion about whether instruction files
bind**, and if behaviour differs between two machines with identical repos, look there first.

**When you cite a preference that isn't in a repo file, name the store it came from.** An uncited
preference is indistinguishable from one you invented.

Paths, audit commands and the incident that uncovered this tier: `docs/reference/copilot-memory-tiers.md`.

## What to store

- Stable user preferences (workflow, style, tooling).
- Reusable repo facts — build commands, conventions, architecture anchors — not already in
  `project-context.md`.
- Corrections ("don't do X, here's why") and confirmed approaches that shouldn't be re-litigated.

## What not to store

- One-off details, raw logs, stack traces, large outputs. This file is curated, not a transcript —
  that's what `hooks/session-logger` is for.
- Secrets, credentials, personal or sensitive information.
- **Anything the baseline's own instructions or skills already state.** The project inherits it;
  a second copy just drifts.
