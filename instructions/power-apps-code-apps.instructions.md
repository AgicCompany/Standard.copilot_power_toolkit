---
description: 'Power Apps Code App rules applied while writing app code — SDK, generated services, Dataverse access, and deployment. Full reference lives in docs/reference/power-apps-code-apps-reference.md.'
applyTo: '**/*.{ts,tsx}, **/power.config.json, **/vite.config.*, **/package.json'
---

# Power Apps Code Apps

Code-first web app on Power Platform: **React + TypeScript + Vite**, `@microsoft/power-apps` SDK,
data via Power Apps CLI-generated services. Long-form material — PCF controls, Power BI embedding, AI
Builder, the full deployment and troubleshooting sections — is in
[`docs/reference/power-apps-code-apps-reference.md`](../docs/reference/power-apps-code-apps-reference.md).

## Check for schema drift before writing data access code

**Do this yourself, at the start of any task that reads or writes Dataverse.** Compare the modified
time of `power.config.json` against the newest file under `src/generated/`:

```powershell
(Get-Item power.config.json).LastWriteTimeUtc
(Get-ChildItem src/generated -Recurse -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
```

If **`power.config.json` is newer**, the generated services may no longer match the configured data
sources. Say so before writing code, and offer to regenerate.

Why this is a rule for you rather than a background check: the failure is invisible to every
mechanical gate. Generated types agree with themselves, so TypeScript compiles, lint passes, and
tests that mock at the service boundary pass too. It surfaces at runtime as a Dataverse error about
a missing column or an unset required field — often partially, where some records save and some do
not — while the code you are reading looks entirely correct.

There is also a `dataverse-schema-drift` hook that runs the same comparison when the session starts,
and if it finds drift the warning appears in your starting context. **Check anyway.** It runs once,
at session start, so a data source added or a schema changed during the session is invisible to it —
and the absence of a warning is not evidence that nothing drifted.

Regeneration is one command:

```bash
pa app refresh data-source --name <data-source-name>
```

## Never use `window.confirm`, `alert` or `prompt`

**This is a platform constraint, not a styling preference, and it holds whatever UI library the
project uses — including none.**

Power Apps Code Apps run inside an iframe whose sandbox lacks `allow-modals`. `confirm()` there does
not show a dialog: it **returns `false` immediately**. So "confirm before deleting" becomes "silently
never delete". Nothing errors, the build passes, lint passes, tests pass, and it works perfectly on
localhost — which is where you will test it.

**Use the UI library this project is configured for, and install it if it is not there yet.** Check
`.github/.baseline-manifest.json` — the `ui` field says `shadcn` or `fluent`. shadcn means
`AlertDialog` (`pnpm dlx shadcn@latest add alert-dialog`); Fluent means its `Dialog`.

**Do not hand-roll a dialog, and do not reach for the native `<dialog>` element instead of
installing.** A native `<dialog>` does work inside the iframe — unlike `confirm()`, it is unaffected
by the `allow-modals` sandbox flag — so this is not a correctness trap. It is a **consistency** one:
you get a bespoke component that does not match the app's styling, theming or a11y conventions,
diverges from every other dialog in the project, and has to be maintained by hand forever, all to
avoid one install.

Installing a dependency the convention requires is part of *finishing* the work — see
`copilot-instructions.md`. "Avoiding setup overhead", "out of scope", and "keeping it minimal" are
all the same refusal, and all of them are wrong here.

> Observed three times, 2026-08-01/02, each time with different wording after the previous one was
> named: `window.confirm` because shadcn was absent; then "adding dependencies is out of scope"; then
> a hand-rolled native `<dialog>` to "avoid unnecessary setup overhead". Naming a wrong answer does
> not constrain the space of wrong answers — so the rule is now stated positively: **use the
> configured library, install it if missing.**

> Observed failure, 2026-08-01: asked to confirm before deleting, an agent found no shadcn in the
> project, decided "adding dependencies is out of scope", used `window.confirm`, and justified it as
> "accessible by default through the browser's OS-level implementation". Every step of that is
> reasonable in a normal web app and wrong in a Code App. The rule lived only in
> `shadcn-ui.instructions.md`, so when shadcn was absent the whole file read as inapplicable.

## Generated code is not yours to edit

- `src/generated/services/` and `src/generated/models/` are produced by the CLI. **Never hand-edit
  them** — the next data-source command overwrites your changes silently.
- To pick up a Dataverse schema change, **refresh the data source**:
  `pa app refresh data-source --name <data-source-name>`. Delete-and-re-add is the older workaround
  from when no refresh command existed; it still works but loses the data source's configuration.
- Keep generated files strictly separate from hand-written code.

## Which CLI

**The current CLI is the npm `pa` CLI** (`@microsoft/power-apps-cli`, 1.0.0 GA August 2026). The
older `pac code` commands still run but are the legacy path and do not receive new features.

**This matters beyond tidiness: `pac code` cannot add Dataverse actions or functions at all.** Any
project that needs a Custom API — which is any project doing a multi-row write — must be on `pa`.
Check which is installed before writing commands into a script or a doc:

```bash
pa --version        # npm CLI present
pac code --help     # legacy CLI present
```

Translate Microsoft blog posts and older answers accordingly. Command groups are noun-verb
(`pa app`, `pa auth`, `pa connection`, `pa solution`), and `pa app <command> --help` is the
authority on any flag.

## Adding a Dataverse table

```bash
pa app add data-source --connector dataverse --table <logical-name> --org-url <org-url>
```

- **`--connector dataverse` is the whole connector argument, and `dataverse` is the only accepted
  value.** Not `cds` (the retired Common Data Service name), not
  `shared_commondataserviceforapps` (the connector id used by *other* tooling). Both have been
  produced from memory in real runs and both are wrong. Do not go looking for a connection via
  `pa connection list` either — that is the shape for SQL, SharePoint and Office 365, and applying
  it here is a hunt with no answer at the end.
- **Do not pass an environment argument.** The active auth profile already determines the target —
  confirm it with `pa auth status` beforehand instead.
- **Pass `--org-url https://<org>.crm<N>.dynamics.com`**, the Dataverse URL of the environment in
  `power.config.json`. Without it `pa` may stop and ask for the organization URL, and in an agent's
  terminal that prompt hangs the command. Get it from `pac org who`, **but only after checking that
  its "Environment ID" equals the `environmentId` in `power.config.json`**: `pac` signs in separately
  from `pa` and may be on another environment or tenant, and its URL would then be a valid URL for
  the wrong organization. If they differ, stop and say so. Never take the URL from memory.
- Beyond `--org-url`, the command is the line above. Anything longer for a Dataverse table is a sign
  of guessing; `pa app add data-source --help` settles it.
- **`--table` takes the singular logical name**: `account`, `contact` — not `accounts`, `contacts`.
  The plural is the OData *entity set* name; you will see both in `power.config.json`
  (`"logicalName": "contact"` next to `"entitySetName": "contacts"`). Users will say "the Accounts
  table" because that is the UI label — translate it, do not echo it.
- Generated **files** are named from the entity set, so `--table account` produces `AccountsModel.ts`
  and `AccountsService.ts`. That plural filename is correct, not a mistake.
- Add tables as the app needs them rather than front-loading the environment.
- Confirm the target environment first — `pa auth status`, and check the environment id against
  `power.config.json` before running anything that writes.

Removing one is `pa app remove data-source --connector dataverse --name <data-source-name>`.

For non-Dataverse connectors the shape genuinely is different and does need `pa connection list`
first; see `pa app add data-source --help`.

## Adding a Custom API, action or function

```bash
pa app find-dataverse-api --search "<OperationName>"   # confirm it is discoverable first
pa app add dataverse-api --api-name <OperationName>    # generate the typed service
```

Returns are `IOperationResult<T>`, with complex and table returns as `Record<string, unknown>`.
Flows are added the same way: `pa app add flow --flow-id <id>`. When to reach for a Custom API at
all is the multi-row rule below; how to build one is the `custom-api-authoring` skill.

## Data access

- **Never call a generated `*Service` directly from a component body.** Wrap it in a hook that owns
  loading, error, pagination, and retry state — see `data-fetching.instructions.md` for the
  TanStack Query pattern this baseline uses.
- **Select only the columns you need**, and **always bound each request**. `getAll()` with no options
  uses the SDK's default page size of 500 — 500 rows pulled into the browser to render twenty, and
  only the first 500 ever shown if the returned `skipToken` is ignored.

  The generated `IGetAllOptions` gives you the whole surface, so use it:

  ```ts
  await AccountsService.getAll({
    select: ['accountid', 'name', 'address1_city'],  // never the whole row
    orderBy: ['name asc', 'accountid asc'],           // unique tie-breaker: stable pages
    maxPageSize: 50,                                  // rows per request — do not omit
    ...(skipToken ? { skipToken } : {}),              // the token the previous page returned
  });
  ```

  - **`maxPageSize`** is the page size. Treat it as mandatory, not an optimisation.
  - **`skipToken`** is how you get the next page: pass back the one each response returns. It only
    moves forward, so the UI is "Load more" or infinite scroll, not numbered pages.
  - **Never `skip`.** It is in the generated type, but Dataverse rejects `$skip` with HTTP 400
    ("Skip Clause is not supported in CRM", verified live). A `skip: page * PAGE_SIZE` hook passes
    every mocked test and fails on the first real request.
  - **`top`** caps the *total*, e.g. "the latest 5". With `top` below the page size you get that many
    rows and no next page, so never use it as the page size.
  - **`orderBy`** is required for paging to mean anything; add a unique column as the last key so
    rows with equal values cannot swap between pages.
  - **`filter`** server-side. Fetching everything and filtering with `.filter()` in the component is
    the same bug wearing a different hat.

  Fetching all rows and calling `.slice()` is never the answer.

- **Never interpolate user input into a `filter` string unescaped.** `filter` is a string expression,
  so a search box wired straight into it is an injection surface — and a single apostrophe in a
  company name ("O'Brien Ltd") breaks the query outright, which is how you usually find out.

  Escape single quotes by doubling them, which is the OData string-literal rule:

  ```ts
  const escapeODataString = (v: string) => v.replace(/'/g, "''");

  filter: `contains(name, '${escapeODataString(term)}')`,
  ```

  Prefer a small builder over hand-assembling filter strings at each call site once you have more
  than one or two conditions.
- **Known gaps in generated Dataverse services** — do not burn time working around these as if they
  were bugs in your code:
  - no `$batch`, and no client-side transaction across calls — see the transactional writes section
  - no FetchXML
  - no polymorphic lookups
  - no alternate keys
  - **no `If-Match` / etag on update** — verified in `@microsoft/power-apps`:
    `updateRecordAsync(tableName, recordId, changes)` takes three arguments and no options object.
    There is no way to ask Dataverse to reject a stale write, so **server-enforced optimistic
    concurrency is not available through the generated services.** See the concurrency section
    below for what to do instead.

## Concurrent edits

Any screen where two users can edit the same record needs a deliberate answer to "what happens if
both save?". Silence here is a decision to lose data.

- **You cannot get a server-enforced guarantee here.** `updateRecordAsync` accepts no `If-Match`
  header, so Dataverse will never reject a stale write on your behalf. Any advice that says "send the
  etag back with the update" is written for a different client and cannot be followed with this one.
- **What is achievable: read-before-write.** Capture `modifiedon` when the record is loaded into the
  form, re-read it immediately before saving, and compare. If it changed, stop and surface the
  conflict with a real choice — reload and lose the edits, or overwrite deliberately.
- **Say plainly that this narrows the window rather than closing it.** Two writes inside the gap
  between the re-read and the update still collide. That is a genuine limitation of the generated
  client, not a flaw in the implementation, and it should be stated rather than papered over —
  someone will otherwise assume a guarantee that does not exist.
- A hard guarantee needs the write moved server-side, into a Custom API. For a **single** contended
  row that is a judgement call worth weighing against the cost. For a write touching **more than one
  row** it is not optional — see the next section.
- Capturing the version and never checking it looks like concurrency control in review and is not.
- Last-write-wins is acceptable for low-contention data — but say so explicitly rather than arriving
  there by omission.
- A lock table is a heavier pattern with real failure modes (stale locks after a crashed tab, no
  release on network loss). Use it only where exclusive edit is a genuine domain requirement, and
  always with a server-side expiry. A lock does **not** remove the need for the version check.

Deeper patterns — lifecycle states, retry, conflict UX — are in the `lock-semantics-expert` skill.

## Writes that touch more than one row

**Concurrency is two users on one row. This is one user across several rows, and it is a different
failure.** Each generated service call is its own request and its own transaction, so a sequence of
them is a sequence of independent commits with no rollback between them.

```ts
await RequestsService.create(header);                       // committed
await RequestLinesService.create(lines, id);                // committed
await AssetsService.update(assetId, { status: 'Reserved' }); // throws
```

You are now left with a request and its lines committed and the asset untouched. **`try/catch` does
not rescue this** — it tells you something failed, it does not undo what already succeeded. Nothing
downstream detects it: types agree, the build passes, and the inconsistency surfaces whenever
someone next reconciles the two tables.

**The rule: more than one row written in one user action → the write moves into a Custom API**,
where a synchronous plug-in makes it one Dataverse transaction that rolls back as a unit.

- Apply it by counting rows, not by judging risk. "These will normally both succeed" is how the
  omission gets justified every time.
- **Atomicity comes from the step registration, not the C#.** A Custom API plug-in registered
  asynchronously, or with logic in PreValidation, runs *outside* the transaction and gives no
  rollback at all — while passing a happy-path test identically. Verify the stage; do not assume it.
- Adding a Custom API needs the **`pa` CLI** — `pac code` cannot do it. See the section above.
- **When a Custom API is genuinely unavailable to you** — no plug-in assembly, no registration
  rights — do not just write the sequence. Say plainly which rows can be left orphaned and let the
  user decide. A stated exposure is a decision; an unstated one is a defect.
- Do not substitute a compensating-delete `catch` block. It is a second un-guaranteed sequence run
  under already-bad conditions, and a partial undo is worse than the partial write.

Full detail — pipeline stages, Function-vs-Action, the error-code contract, the outbox pattern for
notifications — is in `docs/reference/dataverse-transactional-writes.md`. The end-to-end procedure
is the `custom-api-authoring` skill.

## The bundle is not a trust boundary

**A rule enforced only in React is not enforced.** The compiled bundle is downloaded by everyone who
opens the app, including users whose role should never see the screens it contains, and from the
browser console they can call any generated service their Dataverse privileges allow.

So, for anything that matters:

- **Security is Dataverse privileges** — roles and access levels decide which rows a user can read
  and write, however they reach them. **Routing, menus and route guards are user experience**: they
  keep people out of screens that would error, they protect no data, and lazy-loading does not change
  that because the chunks are still fetchable by URL.
- **Any rule that must hold is enforced in the Custom API as well** — a status transition, a
  mandatory reason, who may approve. Client-side only is the same as not enforced.
- A server-side `filter` restricting a list to the current user's own rows is **a security control,
  not a performance tweak.** Removing it to "simplify" exposes every row the role can read.

When you implement a permission check in the client, state where its server-side counterpart lives.
If there isn't one, say so — that is the finding.

## SDK and providers

- If the project has a Power Platform provider component (older Microsoft templates generated
  `PowerProvider.tsx`; the `pa` CLI does not), keep it, but **v1.0 apps must not wait on SDK
  initialization** — there is no initialize-then-render gate; blocking on one is a common cause of a
  permanently blank app.
- Pin `@microsoft/power-apps` explicitly and treat a version bump as a change worth testing.

## Configuration and secrets

- `power.config.json` is app configuration, not a secret store.
- Anything reaching the browser is public. Vite only exposes `VITE_`-prefixed variables — see
  `vite-env-and-secrets.instructions.md`. **Never put a connection secret, client secret, or API key
  in a `VITE_` variable.**
- **When a third-party API needs a key, say what the two routes are** rather than stopping at "not in
  the browser": a **Power Platform custom connector** (key stored in the connection — usually cheaper,
  and the right call for plain key-holding APIs) or a **server-side proxy** (Azure Function or your own
  backend — for real server-side logic). Note that `@microsoft/power-apps` exports only `app`, `data`
  and `telemetry`, so the proxy route means acquiring an Entra ID token yourself. Trade-offs in
  `vite-env-and-secrets.instructions.md`; don't design the integration inline.
- Path alias `@` → `./src` is configured in both `vite.config.ts` and `tsconfig.json`; keep them in
  sync or imports resolve in the editor but fail at build.

## Local development and deployment

- **Local run: `dev` is plain `vite`. Never put `pa app run` in it.** `pa app run` always runs the
  `dev` script itself, so `"dev": "concurrently vite pa app run"` restarts itself recursively.
- Check `vite.config` for the `powerApps()` plugin from `@microsoft/power-apps-vite`, which
  Microsoft's template registers. **With it**, running the `dev` script is the whole setup: the
  plugin serves `power.config.json` and prints the Play URL. **Without it**, run `pa app run`, which
  starts a config server and then runs `dev`.
- If the plugin is only added in a named Vite mode (`vite --mode powerapps`), `pa app run` cannot see
  it: it loads the config in `development` mode and may print "failed to load config". Run
  `vite --mode <mode> --port 3000` directly; if no Play URL appears, add
  `pa app run --config-only` in a second terminal.
- Deploy is `pnpm build` **followed by** `pa app push --solution-id <guid>` — chained with `&&`, never `|`. `pa app push`
  ships whatever is in `dist/`, so a push after a failed build silently republishes the previous
  bundle and the change appears not to have worked. Microsoft's docs use `npm`; translate.
- Confirm the target environment before any push — `pa auth status`, and check the environment id
  against `power.config.json`. A push to the wrong environment is not trivially reversible.
- **Always push with `--solution-id <guid>`**, interactively and in a pipeline (`PA_CLI_SOLUTION_ID`).
  Without it the app goes silently into the environment's preferred solution, a per-maker setting
  that can be someone else's working solution. Solution **names are not accepted**, only GUIDs;
  `pa solution list` shows them.
- `pa` and `pac` sign in separately and can point at different tenants: check `pa auth status` before
  `pa` commands and `pac org who` before `pac` commands.
- CI deploys with a service principal cannot be set up in a tenant's default environment (`pa app
  share` rejects its `Default-` name); see the `code-app-deploy` skill.

## Platform limitations to design around

CSP is not supported. Storage SAS IP restrictions are not supported. There is no Power Platform Git
integration, and solution packager/source integration is limited. Application Insights works only
through SDK logger configuration, not native integration. Plan around these rather than attempting
workarounds that fight the platform.
