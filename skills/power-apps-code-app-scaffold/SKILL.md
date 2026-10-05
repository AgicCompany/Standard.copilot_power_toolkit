---
name: power-apps-code-app-scaffold
description: 'Power Apps CLI walkthrough for Power Apps Code Apps — auth, project init, and connecting Dataverse tables as typed data sources. Use when starting a new Code App, AND whenever adding a data source to an existing one. Covers the exact pa app add data-source syntax, including the Dataverse shortcut that needs no connection ID.'
---

# Power Apps Code App Scaffold

Verified against Microsoft Learn (`developer/code-apps/how-to/create-an-app-from-scratch` and
`.../connect-to-dataverse`, current as of this file's authoring). If a command in this skill
disagrees with what a `pa` invocation actually reports, trust the CLI's own `--help` output and
update this file — commands here can drift as the CLI evolves.

## When to Use This Skill

- "Start a new Power Apps Code App"
- "Scaffold a Code App connected to Dataverse"
- "Set up a new React project for Power Platform"
- "Add a Dataverse table to this Code App"

Don't use this for day-to-day feature work in an already-scaffolded app — that's `react-ts.instructions.md` /
`power-apps-code-apps.instructions.md` / the `dataverse-expert` agent's job (select it from the
Copilot Chat agent picker, not `@mention` — see `AGENTS.md`).

## Prerequisites

- Node.js LTS
- **Power Apps CLI** (npm): `npm install --global @microsoft/power-apps-cli`. This is the current
  CLI; the older `pac code` commands are the legacy path and **cannot add Dataverse actions or
  functions at all**. Verify with `pa --version`
- Git
- A Power Platform environment with **code apps enabled** and (if using Dataverse) **Dataverse enabled**
- This baseline, checked out somewhere outside the new project (`.github_general`)

## Step 1 — Scaffold the base Vite/React app

**Decide the package manager first, and write it down.** A new project has no lockfile, so nothing
decides it for you: check `project-context.md`, and if it names none, **ask the user** — npm, pnpm or
yarn — and record the answer there before installing anything. Every later command uses it
(`<pm>`, `<pm-dlx>`: `docs/reference/package-managers.md`), and a second package manager later
means a second lockfile. Microsoft's samples use `npm`; keep their commands only if npm is the choice.

```bash
<pm-dlx> degit github:microsoft/PowerAppsCodeApps/templates/vite my-app
cd my-app
<pm> install
```

### pnpm only: approve dependency build scripts

Skip this section unless the project uses pnpm.

**`pnpm install` will end with `ERR_PNPM_IGNORED_BUILDS`.** pnpm 10+ refuses to run dependency build
scripts until they are approved, and the refusal blocks **every** `pnpm <script>` afterwards — not
just install — because pnpm re-checks dependency status before each run. `pnpm build` fails with a
stack trace from pnpm's own internals that never mentions the cause.

**pnpm writes `pnpm-workspace.yaml` for you** — do not create it, and do not overwrite it. The failed
install leaves it at the project root already listing the packages it found, each with a placeholder
*sentence* where the value belongs:

```yaml
allowBuilds:
  esbuild: set this to true or false
```

**Read the file. Do not assume which packages are in it.** The list is whatever pnpm resolved at that
moment, so it changes as the template's dependencies change — it is not a fixed set.

> Measured: an install in 2026-08 produced four entries — `esbuild`, `keytar`,
> `@azure/msal-node-extensions`, `@azure/msal-node-runtime`. An install days later, from the same
> template, produced **only `esbuild`**, because `@microsoft/power-apps` is pinned `^1.2.5` and a later
> 1.x dropped those transitive dependencies. Any instruction naming a fixed set of packages here is a
> snapshot, and it ages.

Set **every** entry the file contains to `true`, keeping the keys exactly as generated. Then re-run
`pnpm install`. (`pnpm approve-builds` does the same thing interactively.)

The placeholder is not valid YAML-as-config — it parses as a string, so a half-edited file fails the
same way as no file at all. If `pnpm install` still reports ignored builds, the cause is almost always
one placeholder left behind, not a wrong package name.

This is a plain Vite + React + TypeScript app at this point — nothing Power Platform–specific yet.

## Step 2 — Authenticate and select the environment

```bash
pa auth login
```

`pa auth login` opens a browser sign-in (Entra ID). If you have multiple auth profiles, confirm
the active one with `pa auth status` before continuing — a stale profile pointed at the wrong tenant
is a common silent mistake here.

## Step 3 — Turn it into a Code App

```bash
pa app init --display-name "<App Display Name>" --environment-id <environment-id>
```

This wires up `power.config.json` and the Power Platform SDK bindings. Verify it worked:

```bash
<pm> run dev
```

Open the **Local Play** URL it prints, **in the same browser profile** you used to sign in to your
Power Platform tenant (a different profile/incognito window will fail auth silently). Since Dec
2025, Chrome/Edge block localhost access from some contexts by default — see the "Local Network
Access Restrictions" note in Microsoft's quickstart if the local URL doesn't load.

## Step 4 — Connect Dataverse tables

**This step applies to an existing app too, not only a new one.** Adding a table later is the same
command; there is no separate path for it.

Dataverse has a simpler path than other connectors — **no connection ID lookup needed**.

The connector argument is literally `dataverse`, and nothing else works. Both of these have been
produced from memory in real runs and both are wrong:

- `shared_commondataserviceforapps` with a dataset argument — the connector id other tooling uses;
  cost four tool calls in `pa connection list` hunting an ID that was never required
- `cds` — the retired Common Data Service name

Do not add an environment argument either. The active auth profile decides the target; check it with
`pa auth status` beforehand. **`pa app add data-source --help` is the authority on flags** — guessing
aliases is exactly how the two wrong values above got produced.

Do pass `--org-url`: without it `pa` may stop and ask for the organization URL, and an interactive
prompt hangs an agent's terminal. Take it from `pac org who` (its "Org URL") **only after confirming
its "Environment ID" equals the `environmentId` in `power.config.json`**: `pac` signs in separately
from `pa` and can be on another environment or tenant. If they differ, stop and say so. Never take
the URL from memory.

```bash
pa app add data-source --connector dataverse --table <table-logical-name> --org-url <org-url>
```

Example: `pa app add data-source --connector dataverse --table account --org-url <org-url>`

**When the user names the table in the plural — "add the accounts table" — use the singular and say
so in one line.** The plural is the entity set name, which appears in API paths and in
`power.config.json`; the CLI wants the logical name. Silently converting gets the command right and
teaches nothing, so the same user types the plural again next time. One clause is enough: *"using
`account` — the CLI takes the singular logical name; `accounts` is the entity set name."*

This generates, per table:
- `src/generated/models/<Table>Model.ts` — typed model matching the table's schema
- `src/generated/services/<Table>Service.ts` — `.create()`, `.get(id)`, `.getAll(options)`,
  `.update(id, changes)`, `.delete(id)`

**Never present `.getAll()` without its bound.** Quoting this surface as a plain menu is how an
unbounded `getAll()` ends up in the first component someone writes — observed live: this list was
echoed verbatim to a user as "you can build against `.getAll()`", with no mention of paging, in the
turn immediately before a list screen was requested. Always write it as
`getAll({ select, orderBy, maxPageSize })`, paged with the `skipToken` each response returns, and
point at the `dataverse-typed-client` skill for the hook. Never `top` as a page size (it caps the
total and returns no next page) and never `skip` (Dataverse rejects it with HTTP 400).

Repeat once per table you need at this point — don't front-load every table in the environment,
add them as the app actually needs them.

**"The generated service is missing a field" is usually false — check before regenerating.** The
generator pulls the table's **full** entity metadata, not a subset: `account` generates ~349 typed
fields. So the field is almost certainly already in `<Table>Model.ts`. Grep for it first. What is
actually missing, nine times out of ten, is the field in the feature's `select` list — the generated
model is complete and the query is narrow, by design. Fix `columns.ts`, not the data source.

Regenerating "to add a field" that was never absent costs a round trip against a live environment and
produces a byte-identical diff. Observed live 2026-08-03: an agent was told a field was missing, did
not check, ran the full delete + re-add cycle, and reported *"websiteurl is now present"* — `git
diff` on `src/generated` was empty.

Schema changes that genuinely need regeneration use **refresh**:

```bash
pa app refresh data-source --name account
```

Delete-and-re-add is the older workaround from when no refresh command existed. It still works and is
the fallback if refresh does not pick the change up, but it loses the data source's configuration:

```bash
pa app remove data-source --connector dataverse --name account   # the table LOGICAL NAME, singular
pa app add data-source --connector dataverse --table account --org-url <org-url>
```

**`--name` takes the logical name** — `account`, the same value `--table` takes. Not `Accounts`, not
`AccountsModel`, not the generated file name. A wrong `--name` value has historically **printed no
error**: the command exits quietly having done nothing, which reads as success and leaves you
regenerating a data source that was never removed. Confirm against
`pa app remove data-source --help` rather than guessing.

**Known gaps in Dataverse code-app support as of this writing** (don't burn time working around
these — they're not implemented yet, not a bug in your code):
- Polymorphic lookups
- FetchXML
- Alternate keys
- Schema/metadata CRUD

For non-Dataverse connectors (SQL, SharePoint, Office 365, etc.), the shape is different — you need
`pa connection list` for the connection ID first. See `pa app add data-source --help` or
Microsoft's "Connect your code app to data" doc; don't assume the Dataverse shortcut generalizes.

## Step 5 — Verify, then push

```bash
<pm> run dev                    # local check
<pm> run build && pa app push --solution-id <guid>     # publish into the project's solution
```

`<guid>` is the id of the solution this app belongs in: run `pa solution list` and ask the user which
one, unless the project already records it (`project-context.md`, project memory, a pipeline
variable). If the right solution does not exist yet, stop: it has to be created, with the project's
publisher, before the first push. Without `--solution-id` the app lands in the environment's preferred
solution, which may be someone else's.

`&&`, never `|`. With a pipe, `pa app push` runs even when the build fails — and since it ships
whatever is already in `dist/`, you silently publish the *previous* bundle and the fix you just made
appears not to have worked.

Confirm before pushing: `pa auth status` for the account, and the `environmentId` in `power.config.json` for the target. A push to the wrong
environment is not trivially reversible.

## Step 6 — Apply this baseline

From the new project root:

```bash
pwsh <path-to>/.github_general/tools/apply-baseline.ps1 -TargetProjectPath "."
```

Then, per `USAGE_APPLY_ANY_PROJECT.md`:
1. Fill `.github/project-context.md` — record the environment name/URL, the Dataverse tables
   connected so far, and the solution (if using solution-aware connection references).
2. If you'll use `azure-mcp` tools, run `Azure: Sign In` once (see `.github/docs/mcp-servers.md`).
3. Run `/setup` to generate a project-specific `copilot-instructions.md` from the now-real codebase.

## Anti-Patterns

- ❌ Running `pa app init` without `--environment-id` — it will bind the app to whatever environment your
  auth profile last pointed at, not necessarily the one you meant.
- ❌ Hand-writing types for a Dataverse table instead of using the generated `*Model.ts` — schema
  drift between your hand-written type and the real table is exactly what
  `dataverse-schema-validator` exists to catch, but it's better not to create the drift at all.
- ❌ Treating `power.config.json` / generated services as something to hand-edit — regenerate via
  `pa app` commands instead; see `instructions/vite-env-and-secrets.instructions.md` for why
  Dataverse auth doesn't belong in `.env` either.
