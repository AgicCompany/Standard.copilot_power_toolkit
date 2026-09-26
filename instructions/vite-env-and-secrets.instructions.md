---
description: 'Vite environment variable conventions and secret-exposure prevention for client-side code'
applyTo: '**/*.env, **/*.env.*, **/vite.config.*, **/vite-env.d.ts'
---

# Vite Environment Variables & Secrets

## The Core Rule

Vite only exposes env vars to client code that are prefixed `VITE_`. Everything else stays
server/build-time only — **but that also means anything you DO prefix `VITE_` gets bundled into the
client-visible JavaScript bundle, in plain text, readable by anyone who opens dev tools.**

- `VITE_API_BASE_URL` → fine, it's a public endpoint.
- `VITE_DATAVERSE_API_KEY` → do not do this. Prefixing a secret with `VITE_` doesn't hide it, it
  publishes it.

If a value is genuinely secret, it does not belong in a `VITE_`-prefixed variable, full stop — there
is no client-side env var pattern that keeps a value both usable in the browser and actually secret.

## Access Pattern

- Read via `import.meta.env.VITE_*`, never `process.env.*` (that's the Node convention; it doesn't
  exist in Vite's client bundle and produces `undefined` at runtime, not a build error).
- Type it: declare a `ImportMetaEnv` interface in `src/vite-env.d.ts` for every `VITE_*` var the app
  reads, so a typo in the var name is a type error, not a silent `undefined` in production.

```typescript
// src/vite-env.d.ts
interface ImportMetaEnv {
  readonly VITE_API_BASE_URL: string;
}
interface ImportMeta {
  readonly env: ImportMetaEnv;
}
```

## File Conventions

- `.env` — committed defaults, safe to be public.
- `.env.local` — local overrides, **never committed** (must be in `.gitignore`; Vite's default
  scaffold already ignores `*.local`, verify it wasn't removed).

**Before telling anyone to put a value in a `.env` file, open `.gitignore` and confirm it is
covered.** Do not assume — check, and say what you found.

The Vite scaffold ignores **`*.local` only**. That covers `.env.local` and nothing else: a bare
`.env`, `.env.development` and `.env.production` are all **tracked by default**. Verify with the
command, not by reading the file, since a pattern can match in non-obvious ways:

```bash
git check-ignore -q .env && echo ignored || echo TRACKED
```

Confirmed failure, 2026-07-28: asked for somewhere safe to keep a key, a model correctly refused the
hardcoded constant and then proposed *"a local-only `.env` value (already gitignored in this repo)"*.
It was not. Following that advice would have committed the credential while the user believed it was
protected — a worse outcome than the original request, arrived at through a helpful-sounding answer.
**A wrong claim about where a secret is safe is more dangerous than no advice at all.**

If it isn't covered, say so and add it before proposing the file:

```
.env
.env.*
!.env.example
```
- `.env.development` / `.env.production` — mode-specific, committed if their contents are non-secret.
- Never commit a file matching `.env*.local` or a bare `.env` containing anything beyond public
  config. `hooks/secrets-scanner` catches obvious leaked-looking values at session end, but don't
  rely on it as the only safety net — the check is pattern-based, not exhaustive. See
  `SAFETY_GUARDRAILS.md`.

## Power Apps Code Apps Specifically

This stack's Dataverse/connector authentication does **not** flow through `.env` at all — it's
handled by `pa auth login` at the CLI level, and by `power.config.json` +
the generated `src/generated/services/*Service.ts` files at the app level. If you find yourself
about to add a `VITE_DATAVERSE_*` variable to hold a token, URL, or client secret, stop — that's a
sign the connection should be added via `pa app add data-source` instead (see
`skills/power-apps-code-app-scaffold`), not wired up manually. Legitimate `VITE_*` vars in this
stack are usually limited to genuinely public things: feature flags, a public app-insights
connection string prefix, non-secret API base URLs for *non*-Power-Platform services.

### Third-party API keys: name the two routes, don't design them here

"Don't put it in `VITE_`" leaves the obvious question unanswered — *then how does the browser call
anything that needs a key?* Name the options and the trade-off; the developer picks a path and gets
into the detail there.

- **Power Platform custom connector** — the key is stored in the *connection*, configured once, and
  the app calls it through the same connection layer it already uses for Dataverse. Right choice when
  you are simply calling someone else's API with a key.
- **Server-side proxy** (Azure Function, your own backend) — the key lives in app settings or Key
  Vault; the browser calls your endpoint instead. Right choice when you need real server-side logic:
  caching, aggregation, business rules, or auth a connector can't express.

**The non-obvious part: `@microsoft/power-apps` exports only `app`, `data` and `telemetry` — there is
no auth or token API.** So the proxy route means acquiring an Entra ID token yourself (MSAL in the
browser, your own app registration, scopes, refresh) to authenticate the *user* to your endpoint. That
is real work, and it is why the connector is usually cheaper for a plain key-holding API. Verified
against the installed SDK typings, 2026-08-04.

And do not "solve" the proxy's own auth with a static value in the client — a Function key in the
query string is the same leak wearing a different hat. What the browser holds must be a short-lived,
per-user token issued at runtime, never a credential shipped in the bundle.

## Anti-Patterns

- ❌ `VITE_SECRET_KEY=...` — see above, this is not secret once built.
- ❌ Reading `process.env.VITE_*` in client code — wrong runtime, use `import.meta.env`.
- ❌ Committing `.env.local` "just this once" — it's in `.gitignore` for a reason; if a value needs
  to be shared with the team, it's either not actually secret (put it in `.env`) or it needs a real
  secret store, not a committed file.
- ❌ Assuming a `VITE_*` var is unset-safe without a fallback — a missing var is `undefined` at
  runtime, not a build failure, unless you've typed it per the pattern above.
