---
name: 'Native Dialog Guard'
description: 'Blocks writing window.confirm / alert / prompt into a Power Apps Code App, where the iframe sandbox makes confirm() return false without ever showing a dialog'
tags: ['power-apps', 'code-apps', 'ui', 'pre-tool-use']
---

# Native Dialog Guard

Denies writing `window.confirm` / `alert` / `prompt` into app source in a Power Apps Code App.

**It only enforces in a Code App.** A file belongs to one when a `power.config.json` sits in the
file's folder or any folder above it, up to the repository root. That covers the root layout, a
nested app (`src/frontend/power.config.json` in a multi-host template) and a repository holding
several apps. `POWER_CONFIG` overrides the search. Anywhere else it allows the write and logs
`not_a_code_app` with the file's path. In a plain React app `confirm()` works; preferring the UI
library's dialog there is a convention, and the instruction layer carries it.

## Why a hook and not an instruction

The rule *is* in the instruction layer — `power-apps-code-apps.instructions.md` and
`shadcn-ui.instructions.md` both state it. It was ignored four times on 2026-08-01/02, each time
with new reasoning, each time after the previous wording had been explicitly banned:

1. `window.confirm`, because shadcn was not installed
2. "adding dependencies is out of scope"
3. "avoid unnecessary setup overhead" → hand-rolled a native `<dialog>`
4. and finally, explicitly: *"despite the baseline instructions naming them as the styling authority
   — I used a native `window.confirm()` ... instead of installing a whole UI library for one dialog"*

Step 4 is why this exists. That is not a rule failing to load, and not a loophole in the wording —
it is a rule being read, named, and overridden. Rewriting the text a fifth time was not going to
work.

`permissionDecision: deny` is the only mechanism in this baseline that has never been talked around,
because a refusal cannot be weighed against the task; it has to be dealt with. `vite-env-guard` uses
it and has never failed a test.

## What It Does

Inspects `preToolUse` payloads for writes to `.ts` / `.tsx` / `.js` / `.jsx` and denies any content
containing a `confirm(`, `alert(` or `prompt(` call, with or without the `window.` prefix.

The denial explains the actual failure mode: Code Apps run in an iframe whose sandbox lacks
`allow-modals`, so `confirm()` **returns `false` immediately** rather than showing anything. "Confirm
before deleting" silently becomes "never delete". Nothing throws, and build, lint and tests all pass
— it only misbehaves in the iframe, never on localhost.

It then names the fix: read `ui` from `.github/.baseline-manifest.json` and install that library's
dialog (`shadcn` → `pnpm dlx shadcn@latest add alert-dialog`).

**Not blocked:** the native `<dialog>` *element*. Unlike `confirm()`, it is unaffected by
`allow-modals` and genuinely works in the iframe. Hand-rolling one instead of installing the
configured library is discouraged in the instruction layer, but it is a consistency problem rather
than a correctness one, so it is not enforced here. A guard that blocks working code trains people
to disable guards.

## Configuration

| Env var | Default | Effect |
|---|---|---|
| `SKIP_DIALOG_GUARD` | unset | `true` disables entirely |
| `DIALOG_GUARD_MODE` | `block` | `warn` emits `additionalContext` instead of denying |
| `DIALOG_GUARD_LOG_DIR` | `logs/copilot/native-dialog-guard` | log location |
| `POWER_CONFIG` | unset (search upwards from the file) | pin the file whose presence marks a Code App |

Every decision is logged — `not_a_code_app`, `guard_passed`, `guard_denied`, `guard_warned` — so a silent guard can be
distinguished from an absent one.

## Limitations

- **Content-based, so it only sees what a tool writes.** A file edited outside Copilot, or a call
  assembled at runtime (`window['con' + 'firm']`), passes. This raises the cost of the mistake; it
  does not make it impossible.
- **Test and spec files are exempt** — stubbing `window.confirm` in a test is legitimate.
- **Comment lines are exempt**, so documentation of the rule does not trip it.
- Skips `node_modules/`, `dist/`, `build/`, `.github/`.
- Verified with a 13-case discrimination probe covering both payload dialects: it blocks the four
  offending forms and allows `AlertDialog`, `<dialog>.showModal()`, test stubs, comments,
  `setPrompt(`, `this.confirm(`, markdown and vendored code. The `node_modules` case initially failed
  — a relative path has no leading `/` — which is precisely why the probe tests allowing as well as
  blocking.
