# Apply To Any Project

This guide explains how to reuse this template package across repositories.

## Prerequisites
- PowerShell 7+
- Read access to this repository
- Write access to the target project folder

## Profiles

`apply-baseline.ps1` copies a **profile-selected subset** of the baseline. A profile decides what
gets copied; it never modifies the baseline itself. An asset that fits no profile ships to nobody,
so it does not stay in the baseline — see `AGENTS.md`.

```powershell
pwsh ./.github_general/tools/apply-baseline.ps1 -ListProfiles
```

| Profile | For |
|---|---|
| `react-vite` | React + TypeScript + Vite web app — Tailwind v4 + shadcn/ui, TanStack Query, react-hook-form + Zod, Vitest, Playwright |
| `power-apps-code-app` | **Default.** Everything in `react-vite`, plus Dataverse, Power Platform, App Insights |
| `power-apps-canvas-migration` | A Code App that replaces a Canvas app: everything in `power-apps-code-app`, plus the Canvas YAML rules and the migration/parity agents and prompts |
| `baseline-authoring` | Working on this baseline itself, or another Copilot config repo |
| `full` | Everything: the union of every profile, plus the two MCP-authoring instructions no profile ships yet |

## What This Does
- Copies the selected profile's assets from `.github_general` into the target `.github/`
- Seeds `project-context.md` and `copilot-instructions.md` from their `.template.md` counterparts
- **Never overwrites those two files once they exist — not even with `-Force`.** They become
  project-owned on first apply. Everything else is baseline-owned and re-syncable.
- Writes `.github/.baseline-manifest.json` recording which profile was applied and when
- Does **not** copy: `tools/`, `docs/examples/`, `USAGE_APPLY_ANY_PROJECT.md`, or `AGENTS.md`
- `.vscode/mcp.json` lands at the **target project root** (`<project>/.vscode/mcp.json`), not under
  `.github/` — that's the only location VS Code reads workspace MCP config from

## Step 1: Apply

```powershell
# default profile (power-apps-code-app)
pwsh ./.github_general/tools/apply-baseline.ps1 -TargetProjectPath "C:\path\to\target-project"

# a plain React/Vite app
pwsh ./.github_general/tools/apply-baseline.ps1 -TargetProjectPath "C:\path\to\app" -Profile react-vite
```

Preview first with `-DryRun` — it prints every copy and prune without touching the filesystem:

```powershell
pwsh ./.github_general/tools/apply-baseline.ps1 -TargetProjectPath "C:\path\to\app" -Profile react-vite -DryRun
```

## Step 2: Fill Project-Specific Placeholders
In the target project, fill:
- `.github/project-context.md` — stack, integrations, environments, constraints
- `.github/copilot-instructions.md` — confirm the stack line and package manager

These are yours from here on; re-running the script will not touch them.

## Re-syncing an existing project

```powershell
pwsh ./.github_general/tools/apply-baseline.ps1 -TargetProjectPath "C:\path\to\app" -Force -Prune
```

- `-Force` refreshes baseline-owned files that already exist in the target
- `-Prune` removes baseline-owned files the selected profile no longer includes — including stale
  assets from an earlier profile, and legacy `hooks/<name>/hooks.json` folders from before the flat
  hook restructure. It only ever removes paths that exist in this baseline, so project-authored
  files are never touched.
- Switching profiles is just `-Profile <new> -Force -Prune`

Run `-DryRun` first on a project you care about.

## Recommended Day-1 Validation
1. Confirm these exist in target project:
   - `.github/SAFETY_GUARDRAILS.md`
   - `.github/docs/WORKFLOW_AUTHORITY.md`
   - `.github/GOVERNANCE_MATRIX.md`
   - `.vscode/mcp.json` (at project root, not under `.github/`)
2. Confirm `.github/project-context.md` is filled.
3. If you'll use `azure-mcp` tools (deployment/best-practices), run `Azure: Sign In` from the VS Code
   Command Palette once — see `.github/docs/mcp-servers.md`. Without this, those tools fail silently.
4. Open Copilot chat and run one planning and one review workflow to validate routing.
5. Run `pwsh ./.github_general/tools/lint-baseline.ps1` against the source before applying, to catch
   baseline issues before they propagate.

## Update Strategy
- Treat this repository as the baseline source; make changes here, then re-sync downstream.
- Never edit a target project's `.github/` for something that should be baseline-wide — it will be
  overwritten on the next `-Force` run.
- New project type? **Add a profile to `tools/baseline-profiles.json`.** Do not delete assets to
  make a project cleaner — that removes them for every other project type too.
