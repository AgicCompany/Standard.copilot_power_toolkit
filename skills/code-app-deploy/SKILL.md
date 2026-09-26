---
name: code-app-deploy
description: 'TRIGGER - read this BEFORE running any CLI command that writes to an environment, especially pa app push, and before answering any question about deploying, publishing, or promoting between environments. Do NOT skip because the user "just wants to push" - confirming which environment the CLI is authenticated to is the step that gets skipped and is the one that is hard to undo. Covers environment verification, correct build-then-push order, and the common push failure modes. SKIP for first-time project setup (use power-apps-code-app-scaffold).'
---

# Code App Deploy

Deployment is where a Code App does something genuinely hard to undo: it overwrites a running app in
a real environment, potentially the one users are in right now.

## Rule zero — confirm the environment before every push

A push resolves its target from **two** pieces of state, and you must check both. The signed-in
account is global CLI state that persists between sessions; the target environment is pinned in the
project's `power.config.json`.

```bash
pa auth status                          # signed-in accounts, and which is active
cat power.config.json                   # read environmentId — this is what the push will hit
```

**Read the `environmentId` out of `power.config.json` and show it to the user alongside the active
account.** There is no `pa` equivalent of the old `pac org who`, so an id is what you have — do not
substitute a guess at the environment's friendly name. If the project keeps a list of environment
ids (a README, a pipeline variable file), resolve it against that and say which source you used.

**Get explicit confirmation before pushing to anything not clearly a dev environment.**
`SAFETY_GUARDRAILS.md` requires this. A push to production is not rolled back by re-pushing — users
see the broken build in between.

To change account:

```bash
pa auth switch --account <user@example.com>
```

## The deploy sequence

Order matters. `pa app push` publishes whatever is in the build output directory — it does not
build for you.

```bash
pnpm install          # 1. dependencies match the lockfile
pnpm lint             # 2.
pnpm build            # 3. produces dist/ — on the default scaffold this is `tsc -b && vite build`,
                      #    so it typechecks too
pa app push         # 4. publishes dist/
```

**Run only the scripts this project actually defines.** Read `package.json` first. The default Code
App scaffold (Vite template + `pa app init`) defines `dev`, `build`, `lint`, `preview` — **no
`typecheck`, no `test`.** Inventing steps costs a real deploy: each of these is a stop-on-failure
gate, so a missing script exits non-zero with `ERR_PNPM_NO_SCRIPT` and halts the sequence before the
push. Run `pnpm typecheck` and `pnpm test` when they exist, skip them when they do not, and say which
you skipped and why.

Where typechecking is not folded into `build`, run it separately — a `vite build` alone does not
typecheck.

**Skipping the build ships the previous bundle.** This is the single most common "my fix didn't
deploy" report — the push succeeds, reports success, and publishes stale output. After building,
confirm `dist/` is newer than the last source change.

**Re-confirm the active account with `pa auth status` immediately before the push**, no matter how
recently you checked. It is global CLI state: another terminal, another agent, or a `pa auth switch`
earlier in the same session can move it between your check and your push. The `environmentId` in
`power.config.json` cannot move that way, but re-read it too if anything has run `pa app init`.

## Solutions and connection references

Once a project has plug-ins, Custom APIs or flows alongside the app, the **solution** becomes the
release vehicle and the push is only one part of it.

- **Push into a named solution:** `pa app push --solution-id <guid>`, or the `PA_CLI_SOLUTION_ID`
  environment variable in a pipeline. **Solution names are not accepted — only GUIDs.**
  `pa solution list` resolves a name to its id.
- **Set a preferred solution on the dev environment** so an interactive first push lands where you
  expect without the flag.
- **Use connection references, never direct connections**, or the solution will not import into
  another environment. `pa connection list-references --solution-id <guid>` shows what a solution
  carries.
- **Promote the managed solution; do not push the app straight into production.** The pipeline
  exports managed from dev and imports to test and prod. A direct push to prod bypasses every gate
  the solution provides.
- **Expect a split repository and document it.** Power Platform Git integration does not cover code
  apps: the React and C# source live in ordinary Git, while the solution is the release artefact.
  This looks broken to whoever inherits the project until it is written down.

## Promoting between environments

Code Apps have **no Power Platform Git integration**, and solution packager/source integration is
limited. Promotion is therefore explicit, not automated:

1. Sign in to the target tenant (`pa auth login`, or `pa auth switch` if the account already exists)
   and verify the `environmentId` in `power.config.json` matches the environment you mean.
2. Confirm data sources exist in the target — connection references and Dataverse tables must be
   present there, with the same logical names. They are not carried by the push.
3. Rebuild with the target's environment variables (`.env.<env>` / build-time `VITE_` values are
   baked into the bundle — a bundle built for dev contains dev URLs).
4. `pa app push`.
5. Smoke-test data access specifically. Most environment-promotion failures are connection/permission
   failures, not code failures.

## Common failures

| Symptom | Cause | Fix |
|---|---|---|
| Push succeeds, app shows old content | `pnpm build` not run, or pushed from a stale `dist/` | Rebuild, confirm `dist/` mtime, push again |
| Blank white app after deploy | App waiting on SDK initialization | v1.0 apps must not gate render on SDK init — see `docs/reference/power-apps-code-apps-reference.md` |
| Auth/401 errors only after deploy | Connection not shared, or missing in target environment | Verify connections in the target; re-add the data source there |
| Data works locally, fails deployed | Local run proxies through `pa app run`; deployed uses real connections | Test with a real connection before promoting |
| Push targets the wrong environment | Stale `pa auth` account, or an `environmentId` from another environment | Check `pa auth status` AND `power.config.json` first |
| CSP / iframe errors | CSP is **not supported** for Code Apps | Do not attempt CSP headers; design around it |

## Local development

Local dev needs the Vite server *and* the Power Platform proxy running together:

```json
{ "scripts": { "dev": "concurrently \"vite\" \"pa app run\"" } }
```

Running `vite` alone gives an app whose data calls fail with no useful error.

## Before you push — checklist

- [ ] Active account and `power.config.json` environmentId shown to the user and confirmed — **re-checked immediately before pushing**
- [ ] Build ran *after* the last source change
- [ ] Every quality script the project defines passes (not "will fix later"); any you skipped are
      named, with the reason
- [ ] No `VITE_`-prefixed secret in the bundle (the `vite-env-guard` hook enforces this)
- [ ] Target environment has the required connections and tables
- [ ] User knows whether this environment has live users
