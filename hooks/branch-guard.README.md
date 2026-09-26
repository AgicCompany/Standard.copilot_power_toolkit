---
name: 'Branch Guard'
description: 'Warns at session start when you are sitting on a protected branch with uncommitted work, before that work becomes expensive to move'
tags: ['git', 'gitflow', 'session-start', 'safety']
---

# Branch Guard

`copilot-instructions.md` can make Copilot **refuse** to commit to `main` — that is verified working.
What nothing did was tell you that you were **already on** `main` with twenty uncommitted files. By
the time the refusal fires, the work is on the wrong branch and someone has to unpick it.

Gitflow branches *before* work starts. This hook is the mechanical half of that rule.

## What It Does

Runs on `sessionStart` and injects `additionalContext` **only when both** are true:

1. the current branch is in `PROTECTED_BRANCHES` (default `main,master,develop`), **and**
2. `git status --porcelain` is non-empty

Being on a protected branch with a clean tree is the normal state at the start of work. Warning there
would fire in every session in every repo and train people to ignore the message — the same
cry-wolf failure `AGENTS.md` warns about, and the reason `scan-secrets` was scoped to skip
`.github/hooks/`.

The injected message lists the first five changed paths, names the Gitflow rule, and prescribes
`stash → branch → stash pop` — explicitly **not** commit-then-move, since committing first puts the
commit on the protected branch, which is the thing being avoided.

It also tells Copilot to raise it **once** and accept the answer, so a deliberate choice to work on
`main` does not get re-litigated every turn.

## Why `sessionStart` and not `userPromptSubmitted`

Only `sessionStart` has **parsed stdout** — its `additionalContext` is injected into the session.
`userPromptSubmitted` fires reliably but its stdout is ignored, so a per-prompt version of this check
cannot reach the model at all. See `docs/reference/hook-payloads.md`.

Running once per chat is the right granularity regardless: branches rarely change mid-conversation.

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `SKIP_BRANCH_GUARD` | unset | `true` disables the hook |
| `PROTECTED_BRANCHES` | `main,master,develop` | comma-separated branch names to guard |

Trunk-based repo? Set `PROTECTED_BRANCHES=main` and the `develop` case disappears.

## Related

- `agents/delivery.agent.md` — the agent that actually performs the stash/branch/commit/PR sequence
- `instructions/gitflow.instructions.md` — the full model (no `applyTo`; never auto-loads)
- The `Git — always in effect` block in `copilot-instructions.md` — the only path those rules reach
  the model automatically
