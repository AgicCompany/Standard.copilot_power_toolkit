# Datasource Onboarding Runbook

Adding a Dataverse table (or another connector) to an existing Power Apps Code App. The exact
command and its traps live in `instructions/power-apps-code-apps.instructions.md` → *Adding a
Dataverse table*; this is the order around it.

## 1. Work in the app folder

The folder holding the `power.config.json` of **the app the data source is for**. It is the
repository root only for a single-app repo; in a multi-host or template-derived repo it is a subfolder
such as `src/frontend/`. Search for `power.config.json` (skipping `node_modules`): if there is more
than one and the request does not say which app, **ask** — never take the first result. Run every
`pa` command **from that folder**: `pa` reads and writes the `power.config.json` it finds there and
generates code next to it, so the wrong folder adds the table to, and regenerates, another app.

## 2. Confirm the target before writing

`pa auth status` (the active account) and the `environmentId` in `power.config.json` (the target). If
you will pass `--org-url`, take it from `pac org who` only after checking its Environment ID equals that
`environmentId`.

## 3. Add it with the CLI — never by editing `power.config.json`

`power.config.json` and `src/generated/` are CLI output. Hand-edits drift from what the CLI would
generate and are overwritten on the next run.

```bash
pa app add data-source --connector dataverse --table <singular-logical-name> --org-url <org-url>
```

Non-Dataverse connectors need a connection id first (`pa connection list`); `pa app add data-source
--help` settles the syntax for either.

## 4. Verify what was generated

Next to `power.config.json`: `src/generated/models/<EntitySet>Model.ts` and
`src/generated/services/<EntitySet>Service.ts` (named from the plural entity set — `AccountsService`
for `account`). Read the model before writing code against it; it is the ground truth for the columns
the app can see.

## 5. Use it through a feature `api/` hook

The generated service is a transport. Call it from a hook in the owning feature's `api/` folder (or
`src/lib` for an app-wide service), never from a component — the `data-fetching` and
`power-apps-code-apps` instructions carry the query rules (`select`, `maxPageSize` + `skipToken`, no
`$expand`, failures resolve rather than reject).

## 6. Before reporting done

- The project's build passes (`<pm> run build` — `docs/reference/package-managers.md`).
- Errors from the new calls are mapped to user-safe messages, not rendered raw.
- `power.config.json` and the generated files are committed together with the code that uses them.
