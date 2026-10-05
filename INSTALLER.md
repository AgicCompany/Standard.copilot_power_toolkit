# Installer — handover notes for the npm / npx version

For whoever packages this baseline for `npx`. It describes what the current installer does, the
behaviour that has to survive the move, and how to prove the new one matches the old. None of it is
prescriptive about *how* you build it.

## What the installer does

Copies a **profile-selected subset** of this repository into a target project's `.github/` folder.
The profile decides what is copied; nothing in this repository is ever modified.

- Logic: `tools/apply-baseline.ps1` (420 lines).
- Data: `tools/baseline-profiles.json` — `common`, `alwaysExcluded`, `retired`, `uiVariants`, and the
  `profiles` with their `extends` chains. **The installer and `tools/lint-baseline.ps1` both read
  this file**, so it is the single source of truth for what ships where.

**The current script requires PowerShell 7**, not Windows PowerShell 5.1:
`[System.IO.Path]::GetRelativePath` is .NET Core only. So wrapping the `.ps1` behind `npx` works, but
puts a PowerShell 7 dependency on every user — which is the dependency the move to `npx` is meant to
remove.

## Command surface today

| `apply-baseline.ps1` | Meaning | Default |
|---|---|---|
| `-TargetProjectPath <dir>` | Project to install into | required. For `npx`, the current directory is the natural default |
| `-Profile <name>` | `react-vite`, `power-apps-code-app`, `power-apps-canvas-migration`, `baseline-authoring`, `full` | **remembered** from the target's receipt; else `power-apps-code-app` |
| `-Ui shadcn\|fluent` | UI library variant | **remembered**; else `shadcn` |
| `-Force` | Overwrite existing **baseline-owned** files | off |
| `-Prune` | Remove baseline-owned files the profile no longer includes | off |
| `-DryRun` | Print what would happen, write nothing | off |
| `-ListProfiles` | Print profiles and descriptions | — |

## The README already documents the npx command

`README.md` → *Apply it to a project* describes the npx surface users will be told to run: from the
project root, with `--profile`, `--ui`, `--force`, `--prune`, `--dry-run` and `--list-profiles`,
mirroring the script's flags above. **Treat it as the spec.** If the CLI ends up with different flag
names, a positional target path, or subcommands, change the README in the same PR, or users follow
instructions that do not work.

**Before publishing, fill in the package name.** It is a single placeholder token:

```bash
git grep -n "<npm-package-name>" -- README.md      # the occurrences to replace (this file only explains them)
```

Replace each with the published name (e.g. `@scope/package`), and delete the README's blockquote
that begins *"`<npm-package-name>` is a placeholder"* — it tells users to fall back to the PowerShell
script until the package exists.

## Behaviour that must be preserved

Each of these exists because its absence was a real, observed bug.

1. **Profile resolution.** Flatten `extends` recursively (error on a cycle), prepend `common`, then
   apply the `uiVariants` swap: add its `add` list, and treat its `remove` list as a **file-level
   exclusion** — not merely as strings to delete from the include list. shadcn and Fluent are
   mutually exclusive, not additive: both declare `applyTo: '**/*.{tsx,jsx}'`. *Bug it prevents:*
   removing only the include strings missed any profile that reaches a file through a broad glob —
   `full` includes `**`, so `-Profile full` shipped both styling authorities at once.

2. **Glob semantics** (baseline-relative, forward slashes): `**/` spans any number of directories,
   `**` spans anything, `*` stays inside one path segment. `alwaysExcluded` wins over every include.

3. **Remembered profile and UI.** Neither has a hard default when a receipt exists. If `-Profile` or
   `-Ui` is omitted, read it back from `.github/.baseline-manifest.json`. *Bug it prevents:* a plain
   re-sync of a `react-vite` project used to switch it to `power-apps-code-app` and inject Dataverse
   instructions into a project with no Dataverse. Receipts written by older versions lack `ui` and
   `templateHashes` — tolerate missing fields.

4. **Project-owned files: seeded once, never overwritten — not even with `-Force`.**

   | Source in this repo | Lands at |
   |---|---|
   | `copilot-instructions.template.md` | `.github/copilot-instructions.md` |
   | `project-context.template.md` | `.github/project-context.md` |
   | `docs/project-memory.template.md` | `.github/docs/project-memory.md` |
   | `vite-env-guard.allow.template` | `.github/vite-env-guard.allow` |

   *Bugs it prevents:* `-Force` used to replace a project's tailored instructions with the generic
   template, and to wipe the accumulated project memory — the one file whose purpose is to survive.

5. **Template drift warning.** Store each template's SHA-256 in the receipt at seed time. On a later
   run, if a template changed upstream, **warn** and name the file — do not overwrite. Without this,
   template fixes never reach existing projects and nothing says so.

6. **`.vscode/**` lands at the project root**, not under `.github/` — VS Code only reads
   `.vscode/mcp.json` there. It is never pruned.

7. **`-Prune` touches only paths this baseline could own.** Build the set of every non-excluded,
   non-template source path; delete a target file only if it is in that set **and** not in the
   current profile. Project-authored files must be untouchable. Case-insensitive comparison. After
   pruning, remove empty directories, and remove legacy `.github/hooks/<name>/hooks.json` folders.
   **Retired files** (`retired` in `baseline-profiles.json`, each a `path` plus `sha256` list) are
   files the baseline used to ship: add one to the prune set only when the target file's SHA-256,
   computed with every CR byte removed, is in its list. *Bugs it prevents:* excluding a file stops it
   being copied but also stops prune owning it, so old copies stay forever; and the receipt is not
   proof of ownership, because an install without `--force` records paths it skipped, so trusting
   it would delete a project's own file.

8. **Relative paths must survive Windows 8.3 short names** (`C:\Users\LONGNA~1\…`). A substring-based
   relative path silently produces garbage when one side is short-named. Normalise both sides first
   (in Node: `fs.realpathSync.native`, then `path.relative`, then forward slashes).

9. **The receipt**, written unless dry-run: `profile`, `ui`, `appliedUtc`, `source`, `fileCount`,
   `templateHashes`, `files`.

## What changes because of npm

- **`source` in the receipt** is currently the baseline's local path. Under `npx` that is an
  ephemeral cache directory. Record **`<package>@<version>`** instead — which also gives every project
  a way to tell which baseline version it is on, something the current receipt cannot do.
- **The drift warning's `code --diff` suggestion** points at the template in the baseline folder. In
  the `npx` cache that path may not survive; print the template content or a URL to the tagged
  version instead.

## What goes in the package

npm publishes everything not ignored unless `package.json` has a `files` whitelist. **Use one.**

**Must ship:** `agents/`, `instructions/`, `prompts/`, `skills/`, `hooks/`, `docs/` (not
`docs/examples/`), `ISSUE_TEMPLATE/`, `eslint/`, `.vscode/`, the root `*.template.md` and
`vite-env-guard.allow.template`, the root docs that profiles copy (`QUICK_REFERENCE.md`,
`SAFETY_GUARDRAILS.md`, `GOVERNANCE_MATRIX.md`, `PROGRESSIVE_DISCLOSURE.md`,
`ISSUE_TEMPLATE_PROGRESSIVE_DISCLOSURE.md`), **`tools/baseline-profiles.json`**, and the CLI itself.
`README.md` is in the package as its own documentation (npm includes it regardless), but it is
**never copied into a project**: it is in `alwaysExcluded`.

**Must not ship:** `AGENTS.md`, `INSTALLER.md`, `USAGE_APPLY_ANY_PROJECT.md`, the other `tools/`
scripts, `.github/` (this repository's own CI), `logs/`, `.claude/`.

Note the asymmetry: `tools/**` is in `alwaysExcluded` — never copied **into projects** — but
`tools/baseline-profiles.json` must be **in the package**, because the installer reads it.

**Verify with `npm pack --dry-run`**, which lists exactly what would be published.

## Two byte-level properties npm can break

These are not style. Each makes hooks fail with no visible error.

- **`.sh` hooks must be LF.** With CRLF the shebang reads `bash\r` and every bash hook dies with
  "bad interpreter". `.gitattributes` enforces LF on checkout; publish from a clean checkout.
- **`.ps1` hooks must keep their UTF-8 BOM.** Windows PowerShell 5.1, which the Copilot host uses,
  reads BOM-less files as cp1252.

### Known issue — executable bit on `.sh` hooks

All 17 `hooks/scripts/*.sh` are stored in git as `100644`, **not executable**. The hook configs
invoke them by path (`"bash": ".github/hooks/scripts/build-gate.sh"`), which on macOS and Linux
requires the executable bit — so the bash mirrors may fail with "permission denied" there. This is
**pre-existing**, not caused by npm, and not yet verified against the host's actual invocation;
CI does not catch it because `tools/probe-hooks.sh` runs `bash script.sh` explicitly.

npm also loses executable bits when a package is published from a Windows working tree. The robust
fix is for the installer to `chmod 755` the copied `hooks/scripts/*.sh` on non-Windows platforms.

## Proving the new installer matches the old one

Run both into fresh, empty directories and compare the resulting trees. For each profile, and for
`power-apps-code-app` with each UI variant:

```powershell
pwsh ./tools/apply-baseline.ps1 -TargetProjectPath ./out-ps  -Profile react-vite
npx <package> ./out-npx --profile react-vite
# compare every file path and SHA-256 under ./out-ps and ./out-npx,
# ignoring .github/.baseline-manifest.json's appliedUtc and source fields
```

Then the stateful cases, which a single fresh install does not exercise:

| Scenario | Expected |
|---|---|
| Edit `.github/copilot-instructions.md`, re-run with `--force` | the edit survives |
| Re-run with no `--profile` on a `react-vite` project | stays `react-vite` |
| Apply `power-apps-code-app`, then `--profile react-vite --prune` | Dataverse assets removed; project-authored files and `.vscode/` untouched; no empty folders |
| Change a template, re-run | drift warning names the file; the project copy is not overwritten |
| `--dry-run` | nothing written, including the receipt |
| `.github/README.md` is a shipped baseline version; re-run with `--prune` | removed |
| Project's own `.github/README.md`, installed over **without** `--force`, then `--prune` | untouched |
| The baseline README, edited by the project, then `--prune` | untouched |
