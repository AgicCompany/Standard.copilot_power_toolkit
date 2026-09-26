---
name: 'Build Gate'
description: 'Runs TypeScript type-checking and lint (if configured) at session end so a session cannot quietly end with a broken build'
tags: ['quality', 'typescript', 'build', 'session-end']
---

# Build Gate

`checklist.agent.md` and `review.agent.md` both describe "Build ✓ / Lint ✓" as part of their quality
gate — but that was purely conversational: an agent asked to check, not something guaranteed to
actually run. This hook makes that check deterministic instead.

## What It Does

**Registered on both `sessionEnd` and `Stop`.** Verified live in VS Code Copilot Chat: `sessionEnd`
never fires (not on new chats, window reloads, or a full quit) while `Stop` fires after every
completed turn. Copilot CLI may differ, so both are registered - see `docs/reference/hook-payloads.md`.

Running per-turn is **better** than at session end: a type error or a `tailwind_not_installed`
finding surfaces while the change is fresh. The `GATE_MIN_INTERVAL_SEC` throttle (default 180s)
stops it running a full typecheck after every message.

On each trigger:
1. Detects the package manager from the lockfile present (`pnpm-lock.yaml` / `yarn.lock` /
   `package-lock.json`) — doesn't assume one.
2. If `tsconfig.json` exists, runs the type check. If the root `tsconfig.json` uses project
   references (`"references": [...]`, common in Vite scaffolds), runs `tsc -b` — plain `tsc --noEmit`
   does not follow references and would silently check nothing. Otherwise runs `tsc --noEmit`.
3. If `package.json` defines a `lint` script, runs it.
4. Reports pass/fail. In `warn` mode (default) it never blocks — it just tells you. In `block` mode
   it exits non-zero on failure.

5. Runs **convention checks** (below).

If neither a `tsconfig.json` nor a `lint` script exists and no convention findings are raised, it
skips cleanly.

## Convention Checks

Some conventions cannot be enforced by instruction prose. These three are checked mechanically:

| Check | Detects |
|---|---|
| `tailwind_not_installed` | `.tsx`/`.jsx` emitting Tailwind utility classes while `tailwindcss` is absent from `package.json` |
| `cn_without_tailwind_merge` | a local `cn()` helper while `tailwind-merge` is absent — i.e. a hand-rolled stub that concatenates instead of resolving conflicting utilities |
| `component_without_test` | a component in `src/components/` with no sibling `.test.tsx` (`src/components/ui/**` is exempt — that's shadcn CLI output) |

### Why these are hooks and not instructions

The Tailwind one is the reason this section exists. The equivalent instruction failed to bind in
**six** separate contexts during live testing — direct prompt, planning, TDD execution, refactor,
checklist review, and code review — and it is the one failure mode nothing else can see: a component
emitting Tailwind classes into a project without Tailwind **compiles, type-checks, lints, builds and
passes every test** while rendering completely unstyled.

Every check here must be **mechanical**, with no judgement call. Anything requiring interpretation
belongs in an instruction file or a review agent, not here.

The Tailwind pattern deliberately only matches recognisable Tailwind values (`px-4`, `bg-primary`,
`text-sm`, `flex`) so bespoke class names like `counter`, `my-class`, or `text-wrapper` do not
false-positive.

## Installation

This hook is part of the `.github_general` baseline — `tools/apply-baseline.ps1` copies
`build-gate.json` and `scripts/build-gate.{sh,ps1}` into your project automatically. To install
standalone:

```bash
cp build-gate.json your-repo/.github/hooks/
cp scripts/build-gate.sh scripts/build-gate.ps1 your-repo/.github/hooks/scripts/
chmod +x your-repo/.github/hooks/scripts/build-gate.sh
```

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `GATE_MODE` | `warn` | `warn` logs only; `block` exits non-zero on failure |
| `SKIP_BUILD_GATE` | unset | `true` disables the hook entirely |
| `GATE_LOG_DIR` | `logs/copilot/build-gate` | Where structured JSON log lines are written |
| `GATE_RUN_LINT` | `true` | `false` skips the lint step even if a lint script exists |
| `GATE_MIN_INTERVAL_SEC` | `180` | Minimum seconds between runs. `Stop` fires after **every** completed turn, so without this a full typecheck would run after every message. `0` disables throttling. |
| `GATE_CONVENTIONS` | `warn` | `off` disables the convention checks; `warn` reports them; `block` fails the gate on them **on its own**, regardless of `GATE_MODE` |

## Why `warn` by default

Flip to `GATE_MODE=block` once you trust it isn't going to false-positive on your setup (e.g. a
monorepo where `tsc -b`/`tsc --noEmit` at the repo root isn't the right invocation). Start in `warn`,
watch the log for a few sessions, then tighten it.

## Limitations

- Runs at the project root — for a monorepo or non-standard `tsconfig.json` layout, this may not be
  the right invocation. Adjust the script or disable and rely on your own CI instead.
- `timeoutSec` is 120 in `build-gate.json`; raise it for a large codebase where a cold type-check
  takes longer.
