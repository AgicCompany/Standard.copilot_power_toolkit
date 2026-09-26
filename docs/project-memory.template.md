# Project Memory

Durable, curated facts about this project that should survive across chat sessions. This is a
plain file, not a Copilot platform feature — nothing reads or writes it automatically. It only
works if agents are told to read it (see `instructions/memory.instructions.md`, which does this)
and someone (you or the agent, when asked) appends to it when something durable is learned.

This is a distillation, not a log. If `hooks/session-logger` is active, it captures the raw
session activity separately — this file is the curated "what's actually worth remembering" layer
on top of that, not a duplicate of it.

## Format

Add entries under the relevant category below. Each entry: one line, dated, with enough context to
still make sense in six months.

```
- 2026-07-23: <fact>. Why it matters: <reason>.
```

Delete entries that turn out to be wrong or no longer apply — this file decays fast if left stale.

## Before you add an entry: is it about THIS project, or about the stack?

Ask it every time. You are already editing this file, so the cheap answer is "write it here" — and for
a platform fact that is the wrong answer.

- **About this project** — a decision made here, a quirk of this repo, a convention this team chose.
  → belongs here. That is what this file is for.
- **About the stack** — an SDK limitation, a CLI argument, a framework default, a build-tool
  requirement. True of *every* project using it. → belongs in the **baseline**, which lives outside
  this repo and which you cannot edit from here.

For a stack fact, do both: record it here so this project does not lose it, **and say in your reply
that it is a baseline-level fact, naming the file it belongs in.** That sentence is the only thing
that gets it out of this repo. Without it, every project rediscovers the same limitation, pays the
same investigation cost, and the baseline never learns.

Also check the baseline does not already say it. Duplicating `docs/reference/*` or an
`instructions/*` rule here creates a second copy that drifts out of sync with the original.

> Measured 2026-08-03: an agent added four entries in one turn. Three were stack facts — shadcn now
> defaulting to Base UI rather than Radix, `defineConfig` needing to come from `vitest/config`, and
> React Testing Library's cleanup not self-registering when `test.globals` is false. All three were
> accurate and useful. None was flagged for upstreaming, and the first was **already** documented in
> the baseline's own `docs/reference/shadcn-setup.md`.

## User Preferences

*(How this person likes to work — e.g. "prefers pnpm exclusively," "wants terse commit messages")*

## Recurring Facts

*(Stable repo/architecture facts that aren't already obvious from `project-context.md` — e.g. a
non-obvious build quirk, a naming convention not written down elsewhere)*

## Lessons Learned

*(Corrections or confirmed approaches worth not re-litigating — e.g. "don't mock Dataverse calls in
integration tests, we got burned by that once" or "single bundled PR is preferred over many small
ones for this kind of refactor")*
