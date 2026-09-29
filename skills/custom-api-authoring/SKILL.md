---
name: custom-api-authoring
description: 'TRIGGER - read this BEFORE writing any handler that changes more than one Dataverse row in a single user action: a submit that also writes lines or history, a status change that touches another table, an approve/close/cancel action, or anything followed by "and then update". Do NOT skip because the writes "will normally succeed" - a sequence of generated-service calls has no rollback, so a failure on the third call leaves the first two committed with no error the user can act on. Covers the decision test, Custom API configuration, the plug-in shell, the CLI commands that generate the typed client, and calling it from the app. SKIP for single-row writes (use dataverse-typed-client) and for two users editing one row, which is concurrency, not atomicity.'
---

# Custom API Authoring

A Code App cannot write more than one row atomically. This skill moves that write server-side and
wires the typed client back to the app.

Transaction semantics, the pipeline-stage table, the outbox pattern and the Function-vs-Action rule
are in `docs/reference/dataverse-transactional-writes.md`. Read it once; this skill is the procedure.

## Step 1 — Confirm the operation actually needs this

Count the rows written by one user action. **Two or more → continue. One → stop**, use a generated
service and the `dataverse-typed-client` skill.

Also stop if the problem is two users editing the same row. That is optimistic concurrency, a
different mechanism, covered in `power-apps-code-apps.instructions.md`.

**If the project has no plug-in assembly and no route to registering one**, do not proceed silently.
Tell the user the writes will not be atomic, name which rows can be left orphaned, and let them
decide. Do not substitute a compensating-delete `catch` block — see the reference for why that is
worse than the exposure it tries to fix.

## Step 2 — Name the operation and its parameters

- `PascalCase` verb-object, publisher-prefixed: `app_SubmitRequest`, `app_CloseCommitment`.
- Parameters are primitives and GUIDs. **Complex types are not supported** — pass JSON strings and
  parse server-side.
- Decide Function vs Action now: **anything that writes, and anything taking a string parameter,
  must be an Action.** A Function is GET, so string values containing `: / & % ? +` are rejected with
  HTTP 400 — and JSON always contains `:`. This fails only once a real payload is passed, so it will
  not show up in a first test.

## Step 3 — Build the rules as plain classes

Put the decision logic in classes with no SDK types in their signatures, so they are testable in
milliseconds with no environment. The plug-in is a shell around them.

Every branch gets a test that permits it and one that denies it. Every error code gets a test that
provokes it.

## Step 4 — Write the plug-in

Follow `instructions/dataverse-plugins.instructions.md`, which carries the sandbox rules —
statelessness, no async, the error contract, re-entry guards.

The shell is: load, apply the rule, persist, record history, queue any notification as a row.

### Shipping the plug-in

Check the project first: a `.csproj` built with `Microsoft.PowerApps.MSBuild.Plugin` (what
`pac plugin init` generates) produces a **plug-in package** (`.nupkg`); without it, a plain assembly.
The package is the route to prefer, since it can carry dependent DLLs such as the rules from Step 3.
All of the following was verified in a live environment:

- **A package must target `net462`** (or `net471`). Microsoft documents 4.6.2 to 4.8 for plug-in
  assemblies, but uploading a package built for `net48` was rejected: "Supported dotnet frameworks
  are 'net471' and 'net462'".
- **The first registration is manual**: Plugin Registration Tool (`pac tool prt`), *Register New
  Package*, into the project's solution. `pac plugin push` cannot create it; it requires the id of an
  existing package.
- **Updates**: `pac plugin push --type Nuget --pluginId <package id> --pluginFile <.nupkg>
  --environment <org url>`. New `IPlugin` classes in the package are registered by the push.
- **Build with `--no-incremental`, then check the `.nupkg` contents before pushing.** An incremental
  Release build refreshed the DLL but kept the old package, without the new class; it uploaded
  cleanly and failed only when the Custom API ran.

## Step 5 — Register the step, then verify the stage

**This is the step that decides whether you get a transaction at all.** Register the Custom API
implementation synchronously in **MainOperation**.

Then confirm it rather than assuming it: open the step in the Plug-in Registration tool, or query
`sdkmessageprocessingstep`, and check the stage and that execution mode is synchronous. An
asynchronous step returns success and writes later, with no rollback; a PreValidation step runs
before the transaction opens. Both pass a happy-path test identically.

State which stage you verified when you report the work done.

## Step 6 — Generate the typed client

**Read `package.json` and run only the CLI the project actually uses.** The current CLI is the npm
`pa` CLI; `pac code` is the legacy path and **cannot add Dataverse APIs at all**. If the project is
still on `pac code`, that is the blocker to raise first.

```bash
pa app find-dataverse-api --search "app_SubmitRequest"     # confirm it is discoverable
pa app add dataverse-api --api-name app_SubmitRequest      # generates the service
```

`find` first is not ceremony: if the operation does not appear, it is not published to the
environment the app is pointed at, and `add` will fail with a less obvious message.

Flags change between CLI versions. **`pa app add dataverse-api --help` settles the current syntax** —
use it rather than trusting the flags above if anything errors.

## Step 7 — Call it from the app

Wrap it in a mutation hook like any other write. It is still a network call that can fail.

```ts
import { SubmitRequestService } from '@/generated/services/SubmitRequestService';

const result = await SubmitRequestService.app_SubmitRequest(requestId, payloadJson);
```

- Returns `IOperationResult<T>`; complex and table returns arrive as `Record<string, unknown>`, so
  type them at the boundary yourself rather than spreading `unknown` through the app.
- **Map the error code to a message** — the server sends a code, not prose. An unmapped code must
  fall back to a generic message and log the raw value, never render blank.
- **Invalidate every query the operation touched**, not just the obvious one. A Custom API writing
  four tables leaves four caches stale; the list the user returns to is usually the one forgotten.

## Step 8 — Check before reporting done

- The step is registered **synchronous, MainOperation** — verified, not assumed.
- Each error code has a test that provokes it and a client mapping.
- The operation is an **Action** if it writes or takes a string parameter.
- Any send (mail, webhook, Teams) is a queued row, not a call inside the transaction.
- Query invalidation covers every table the API wrote.
- **If you skipped any of these, name which and why.** A skipped check stated is a decision the user
  can act on; a skipped check unstated is the defect this baseline exists to prevent.
