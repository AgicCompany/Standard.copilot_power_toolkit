---
name: 'Vite Env Guard'
description: 'Blocks writes that put a secret-looking value behind a VITE_ prefix, because everything VITE_-prefixed is compiled into the client bundle and is public'
tags: ['security', 'secrets', 'vite', 'pre-tool-use']
---

# Vite Env Guard

`instructions/vite-env-and-secrets.instructions.md` explains the rule. This hook enforces it.

**The rule**: Vite only exposes environment variables prefixed `VITE_` to client code — and anything
exposed to client code is **compiled into the bundle and publicly readable**. A `VITE_`-prefixed
secret is not "configuration", it is a published credential. In a Power Apps Code App that bundle is
served to every user of the app.

This is the highest-consequence, easiest-to-make mistake in the stack: the code works perfectly, so
nothing surfaces the problem until the secret is already shipped.

## Why a hook and not an instruction

An instruction is advice the model may or may not apply on any given turn. A `preToolUse` hook is
deterministic — it inspects the write *before* it happens and can refuse it.

This is also the one hook event where refusal reaches the model: `preToolUse` stdout is **parsed**,
so returning `{"permissionDecision":"deny","permissionDecisionReason":"..."}` blocks the call *and*
gives Copilot the reason, which it can then act on. (`postToolUse` stdout is ignored — see
`lint-fix-on-edit.README.md`.)

## What It Does

On any `edit`/`create` targeting a `.env`-family file, it scans the content being written for
assignments matching `VITE_*` where the **variable name** looks secret-bearing:

`SECRET`, `KEY`, `TOKEN`, `PASSWORD`, `PWD`, `CREDENTIAL`, `PRIVATE`, `CONNECTION_STRING`,
`CLIENT_SECRET`, `API_KEY`, `SAS`, `CERT`

Matching a name pattern rather than guessing at value entropy keeps false positives low and the
reason message specific.

Allowed through: `VITE_API_URL`, `VITE_ENVIRONMENT_NAME`, `VITE_APP_TITLE`, and any non-`VITE_`
variable (those stay server-side and never enter the bundle).

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `VITE_ENV_GUARD_MODE` | `block` | `block` denies the write; `warn` allows it but returns the reason as context |
| `SKIP_VITE_ENV_GUARD` | unset | `true` disables the hook entirely |
| `VITE_ENV_GUARD_PATTERNS` | see above | Comma-separated extra name fragments to treat as secret-bearing |
| `PUBLIC_ENV_PREFIXES` | `VITE_` | Comma-separated build-tool prefixes that reach the browser. Set to `NEXT_PUBLIC_` for Next, or list both. **Unset, a `NEXT_PUBLIC_` secret is not seen at all** — the guard matches on the prefix. |

## Limitations

- Only inspects `.env`-family files. A secret hardcoded directly into a `.ts` file is not caught
  here — `secrets-scanner` covers that ground.
- Only sees content passed through the tool call. A secret written by a shell command the agent runs
  (`echo ... >> .env`) bypasses this; `tool-guardian` is the layer for that.
