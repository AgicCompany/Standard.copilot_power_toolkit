---
name: 'Lint Fix On Edit'
description: 'Runs eslint --fix (and optionally prettier) on each file the agent writes, so the next read sees corrected code instead of accumulating drift until session end'
tags: ['lint', 'formatting', 'post-tool-use', 'react', 'typescript']
---

# Lint Fix On Edit

`build-gate` catches lint and type errors at **session end** — after the agent has already built on
top of whatever it got wrong. This hook closes the gap for the mechanically-fixable half: import
order, quote style, spacing, `const` vs `let`, unused-import removal.

## Why this is a fixer, not a reporter

`postToolUse` **stdout is ignored by the host** — nothing this hook prints reaches the model. So it
cannot be used to tell Copilot "you made a mistake"; that path does not exist for this event.

What it *can* do is change the file on disk. The agent's next read of that file sees the corrected
version, which is why auto-fix works here and reporting does not. Anything requiring the model to
*know* about a problem belongs in `build-gate` (session end) or a `preToolUse` guard (blocks with a
reason).

## What It Does

After a successful `edit` or `create` tool call:

1. Extracts the file path from `toolArgs` (a JSON **string** in the payload — it needs a second
   parse; this is the field that silently broke `tool-guardian` before).
2. Skips anything that isn't `.ts`/`.tsx`/`.js`/`.jsx`/`.mjs`/`.cjs`, and skips `node_modules/`,
   `dist/`, and `src/generated/` — **generated Power Apps CLI output must never be reformatted**, or the
   next `pa app add data-source` produces a noisy diff against your formatting.
3. Runs `eslint --fix` on that single file (fast — one file, not the project).
4. Runs `prettier --write` if `LINT_FIX_PRETTIER=true` and prettier is installed.

Every step is best-effort: a missing tool, a missing config, or a lint failure exits `0`. A
formatting hook must never break the agent's workflow.

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `SKIP_LINT_FIX` | unset | `true` disables the hook entirely |
| `LINT_FIX_PRETTIER` | `true` | Also run `prettier --write` after eslint |
| `LINT_FIX_EXTENSIONS` | `ts,tsx,js,jsx,mjs,cjs` | Comma-separated extensions to process |

## Requirements

- `jq` for the bash variant (PowerShell uses native `ConvertFrom-Json`). No jq → exits `0` silently.
- ESLint installed in the project. No ESLint → the hook does nothing.
