# Copilot Baseline

A reusable GitHub Copilot configuration you copy into a project as its `.github/` folder —
instructions, agents, prompts, skills, and hooks — so Copilot follows your team's conventions
instead of its own defaults.

```bash
npx <npm-package-name> --profile react-vite
```

Run it from your project's root, then reload the VS Code window and Copilot picks it up. It writes
the `.github/` folder (and `.vscode/mcp.json`) and adds nothing to your project's dependencies. No
service, no account. Options and re-syncing: [Apply it to a project](#apply-it-to-a-project).

## Why this exists

Writing `instructions/` files and hoping they bind does not work reliably. That is the finding this
baseline is built around, and most of its design follows from it:

- **Rules that can be checked mechanically are enforced by hooks, not prose.** A `preToolUse` hook
  blocks a `VITE_`-prefixed secret from reaching `.env` even when the model has read the instruction
  saying not to and judged the value harmless. Instructions handle judgement; hooks handle rules.
  One precondition here — "check Tailwind is installed before emitting Tailwind classes" — failed to
  bind in **six** separate contexts as prose before being made a mechanical check.
- **A small always-loaded core.** `copilot-instructions.md` is capped at 70 lines and linted for it.
  Everything else loads by `applyTo` glob, on demand, or not at all. Detail in the core file is paid
  for on every single turn.
- **Profiles decide what ships.** One baseline, several project types — `react-vite`,
  `power-apps-code-app`, `power-apps-canvas-migration`, `baseline-authoring`, `full`. An asset earns its place by belonging to a
  profile once it has been tested in real use; one that fits no profile ships to nobody, so it does
  not stay. New project type means a new profile.
- **It is tested.** `tools/lint-baseline.ps1` catches broken globs, dangling handoff targets, hook
  scripts that crash under the host's PowerShell, and stale governance entries.
  `docs/baseline-acceptance-test.md` is a scripted Copilot session for checking whether the
  conventions actually apply — the same prompts scored 17/17 on one model and failed on another,
  which is worth knowing before you trust a result.

## Prerequisites

| | Why | Install |
|---|---|---|
| **Node.js LTS** | `npx` to apply the baseline; Vite, the test runner, the hooks that call `npx` | `winget install --id OpenJS.NodeJS.LTS -e` |
| **Git** | the delivery agent and several hooks shell out to it | `winget install --id Git.Git -e` |
| pnpm / yarn *(only if the project uses it)* | the baseline names no package manager — the project's lockfile decides; npm ships with Node | `npm install -g pnpm` · `corepack enable` |
| **VS Code + GitHub Copilot Chat** | everything the baseline configures | — |
| **Power Apps CLI** *(Power Apps profile only)* | `pa app init` / `add data-source` / `push`. Replaces the legacy `pac code`, which cannot add Dataverse APIs | `npm install --global @microsoft/power-apps-cli` |
| `gh` *(optional)* | lets the delivery agent open PRs directly | `winget install --id GitHub.cli -e` |
| `jq` *(macOS / Linux)* | **required there** — the `.sh` hook mirrors run on macOS and Linux, and the guards **fail open** without `jq`. Not needed on Windows, where the `.ps1` mirrors run | `brew install jq` · `apt install jq` · Windows: not needed |

**On Windows, nothing PowerShell-related needs installing to *use* the baseline.** The hooks run
under Windows PowerShell 5.1, which ships with the OS.

Two things that bite on a fresh machine:

1. **Restart your terminal after installing anything.** PATH changes don't reach a shell that is
   already open, so the tool you just installed still looks missing.
2. **Pick the package manager once, and write it down.** The baseline follows the project's lockfile
   (`docs/reference/package-managers.md`); a new project has none yet, so `/setup` asks and records
   the choice in `project-context.md`. Mixing two package managers in one project is the defect to avoid.

### Maintaining the baseline itself

Working in a clone of this repository — linting, testing hooks, or applying without npm — also needs
**PowerShell 7+** (`pwsh`, a separate install from the built-in 5.1:
`winget install --id Microsoft.PowerShell -e`). From the clone, one command reports everything
missing at once:

```powershell
powershell -File tools/check-environment.ps1
powershell -File tools/check-environment.ps1 -Profile power-apps-code-app   # adds the Power Apps CLI (pa) check
```

Note `powershell`, not `pwsh` — the checker deliberately runs under Windows PowerShell 5.1, because
*"pwsh is not recognized"* is the first thing you hit on a clean machine.

## Apply it to a project

From the project's root folder:

```bash
npx <npm-package-name> --profile react-vite
```

In a pnpm project, `pnpm dlx <npm-package-name> …` does exactly the same.

| Option | What it does |
|---|---|
| `--profile <name>` | `react-vite`, `power-apps-code-app` (the default for a new project), `power-apps-canvas-migration` (a Code App replacing a Canvas app), `baseline-authoring`, or `full`. **Remembered**: a later run without it keeps the project's profile |
| `--ui shadcn\|fluent` | UI library. `shadcn` is the default; the two are mutually exclusive. Remembered |
| `--force` | Re-sync: overwrite the baseline's own files with the current version |
| `--prune` | Also remove baseline files the current profile no longer includes |
| `--dry-run` | Show what would be written or removed, and change nothing |
| `--list-profiles` | Print the profiles and what each is for |

**Four files become yours after the first run and are never overwritten, not even with `--force`:**
`.github/copilot-instructions.md`, `.github/project-context.md`, `.github/docs/project-memory.md`
and `.github/vite-env-guard.allow`. When the baseline's template for one of them changes, a re-sync tells you so
and leaves the merge to you.

> **`<npm-package-name>` is a placeholder** — the npm package is being published. Until it is, apply
> from a clone of this repository with PowerShell 7:
> `pwsh ./tools/apply-baseline.ps1 -TargetProjectPath "C:\path\to\your-app" -Profile react-vite`
> (full guide: `USAGE_APPLY_ANY_PROJECT.md`).

> **Reading this inside a project's `.github/` folder?** This describes what was installed there.
> The maintainer and installer documentation (`AGENTS.md`, `INSTALLER.md`,
> `USAGE_APPLY_ANY_PROJECT.md`) is not copied into projects — it lives in the source repository,
> <https://github.com/AgicCompany/Standard.copilot_power_toolkit>.

## 📂 Directory Structure

```
.github/
├── copilot-instructions.md   # Always-loaded core context
├── project-context.md        # Project-specific facts (stack, integrations, constraints)
├── GOVERNANCE_MATRIX.md      # Registry of active baseline assets
├── SAFETY_GUARDRAILS.md      # Blocked/confirmation-required actions, secret handling
├── agents/                   # Custom agents, selected in the agent picker (NOT @name)
├── instructions/             # Auto-applied guidance by file pattern
├── prompts/                  # On-demand slash-command templates
├── skills/                   # Bundled task skills, loaded on trigger
├── hooks/                    # Session-lifecycle automation (deterministic, not prose)
└── docs/                     # Runbooks and reference material
```

## 🎯 File Types and Their Roles

### `copilot-instructions.md`
- **Always loaded** into every Copilot session — keep it short (70 lines max, linted) and factual
- Declares the stack, package manager, and pointers to the relevant instructions/agents
- **Role in LLM:** system prompt enhancement

### `agents/` — Custom Agents

Selected via the **agent/mode picker dropdown** in Copilot Chat (the same control used for Ask/Edit/
Agent modes) — or type `/agents` to open the picker. **Not invoked with `@name`** — typing `@plan` in
the chat input does not select the agent; it falls through to VS Code's generic file-reference
autocomplete instead (confirmed empirically, not just from docs). Frontmatter uses `name` (what shows
in the picker — omit it and the filename is used instead) and `description`; there is no `agent:`
field. See `instructions/agents.instructions.md` for the full schema.

| Name in picker | Purpose |
|-----------------|---------|
| `plan` | Deep strategic/architecture planning |
| `small-plan` | Lightweight 4-section plan for small, well-understood tasks |
| `prd` | Write Product Requirements Documents |
| `tdd` | Enforce test-first development |
| `devops` | DevSecOps, automation, compliance |
| `review` | Comprehensive code review with before/after suggestions |
| `checklist` | Structural/quality-gate checklist validation |
| `debug` | Systematic bug investigation |
| `delivery` | Git workflow — branches before work starts, conventional commits, opens the PR. The only agent that runs git |
| `accessibility` | WCAG 2.1/2.2 and inclusive UX guidance |
| `lyra` | Prompt optimization |
| `repo-architect` | Scaffold/validate this baseline's own folder structure |
| `dataverse-expert` | Dataverse schema, query, and integration guidance |
| `power-platform-expert` | Power Apps Code Apps / canvas / Power Platform guidance |
| `canvas-migration-guide` | Canvas → React formula/component migration (`power-apps-canvas-migration` profile) |
| `parity-auditor` | Canvas ↔ React feature parity audits (`power-apps-canvas-migration` profile) |

**Role in LLM:** loaded as the active system prompt only while that agent is selected in the picker.

### `instructions/` — Auto-Applied Guidance

Loaded automatically based on `applyTo` glob match against the file(s) in context.

**A file with no `applyTo` never loads.** Per the VS Code docs: *"If not specified, the instructions
are not applied automatically, but you can still add them manually to a chat request."* A few files
here deliberately have no `applyTo` because their subject has no file-pattern trigger (git workflow,
ADO work items, DevOps culture); those declare it with a `LOADING:` note in the body, and their
operative rules are duplicated into the always-loaded `copilot-instructions.md`. `lint-baseline.ps1`
errors on any other missing `applyTo`.

`GOVERNANCE_MATRIX.md` holds the current, generated table of every instruction file with its exact
`applyTo` and the profiles that ship it. Highlights for the primary stack:

| File | Applies to | Purpose |
|------|-----------|---------|
| `general-coding.instructions.md` | `**` | Universal coding practices |
| `react-ts.instructions.md` | `**/*.{ts,tsx}` | The stack's settled decisions (styling, state, forms, structure) |
| `shadcn-ui.instructions.md` | `**/*.{tsx,jsx}` | **Styling authority** — Tailwind v4 + shadcn/ui, generated-vs-hand-written |
| `data-fetching.instructions.md` | `**/*.{ts,tsx}` | TanStack Query, query keys, cache policy, Dataverse wrapping |
| `forms-and-validation.instructions.md` | `**/*.{ts,tsx}` | react-hook-form + Zod, one schema per form |
| `error-handling.instructions.md` | `**/*.{ts,tsx}` | Boundary placement, user-facing errors, logging |
| `a11y.instructions.md` | `**/*.{tsx,jsx}` | WCAG 2.2 AA rules (catalogue in `docs/reference/`) |
| `performance-optimization.instructions.md` | `**/*.{tsx,jsx}` | Core Web Vitals rules (catalogue in `docs/reference/`) |
| `power-apps-code-apps.instructions.md` | `**/*.{ts,tsx}`, `power.config.json` | Code Apps rules (full reference in `docs/reference/`) |
| `tailwind-v4-vite.instructions.md` | `**/vite.config.*`, `**/*.css` | Tailwind v4 install/config only |
| `vite-env-and-secrets.instructions.md` | `.env*`, `vite.config.*` | `VITE_` prefix rules, client-exposure prevention |
| `fluent-ui-v9.instructions.md` | `**/*.{tsx,jsx}`, with `-Ui fluent` | Alternative styling authority for a native Power Platform look. Replaces `shadcn-ui` and `tailwind-v4-vite` — the two are mutually exclusive |

**Role in LLM:** contextual instructions loaded based on file patterns.

### Size discipline

Instruction files carry the rules that change code. **Long reference catalogues belong in
`docs/reference/`**, linked from a short instruction file and read on demand. This is enforced by
history: `a11y`, `performance-optimization`, and `power-apps-code-apps` had each grown to 25-28KB
and all auto-applied to `**/*.tsx`, so a single component edit loaded ~97KB (~25k tokens) of prose
before Copilot saw any code — the exact opposite of progressive disclosure. `a11y` and
`performance-optimization` are now under 4KB each, with their catalogues in `docs/reference/`.

**`power-apps-code-apps` is the exception, at ~20KB.** It is the largest instruction file and the
biggest single cost of a component edit in a Code App, because it carries the rules that change code
there — the CLI, bounded data access, multi-row writes, the trust boundary. It is the first candidate
if the per-edit cost needs cutting again.

### `prompts/` — Reusable Prompt Templates

On-demand templates, invoked via slash command (e.g. `/create-prd`). Notable ones:

- `session-kickoff.prompt.md` — high-signal task framing (goal/scope/constraints/DoD)
- `code-review.prompt.md`, `code-review-checklist.prompt.md` — review workflows
- `create-prd.prompt.md`, `generate-tasks.prompt.md`, `process-task-list.prompt.md` — PRD → tasks → execution pipeline
- `parity-audit.prompt.md`, `migration-slice.prompt.md` — Canvas → React parity work (`power-apps-canvas-migration` profile)
- `.it.prompt.md` variants — Italian-language equivalents of the same workflows

**Role in LLM:** loaded as a user prompt template only when explicitly invoked.

### `skills/` — Bundled Task Skills

Folder + `SKILL.md`, loaded in full when triggered — treat size as a real cost even though loading
is on-demand. For Code Apps they include `power-apps-code-app-scaffold` (the guided path for a
brand-new app: `pa` CLI sign-in → init → connect Dataverse tables), `dataverse-typed-client`,
`custom-api-authoring` (writes that touch more than one row) and `code-app-deploy`; general ones
include `component-scaffold` and `frontend-design`.

Which skills a project actually has depends on its profile — `skills/README.md` shows how to list
them.

### `hooks/` — Session-Lifecycle Automation

**Flat structure, not per-hook folders**: `hooks/{name}.json` + `hooks/{name}.README.md`, with all
scripts shared under `hooks/scripts/`. This is required, not a style choice — GitHub Copilot's hook
discovery only scans flat `.github/hooks/*.json`; it does not recurse into subfolders. A `hooks.json`
nested inside a per-hook subfolder is invisible to the host, permanently, regardless of whether the
script itself is correct — confirmed against the authoritative hooks reference after a full session
of debugging why hooks never fired.

Every hook also ships both a `.sh` and a `.ps1` implementation (`{name}.json` declares both `"bash"`
and `"powershell"`) — separately necessary: on a native Windows host without bash on PATH (no
WSL/Git Bash selected), a bash-only hook fires silently nowhere, no error, nothing in the logs.
`tools/lint-baseline.ps1` checks both the flat-file requirement and the bash/powershell pairing.

Deterministic scripts (not prose) triggered on session/tool events — more reliable than an
instruction the model has to remember to follow:

- `secrets-scanner`, `tool-guardian`, `governance-audit` — security
- `session-logger` — raw audit trail
- `dependency-license-checker` — license compliance
- `build-gate` — deterministic type-check (`tsc -b` or `tsc --noEmit`, whichever the project's
  `tsconfig.json` actually needs) + lint check at session end (warn by default; set `GATE_MODE=block`
  once trusted)
- `memory-reminder` — surfaces `.github/docs/project-memory.md` at session start so the memory mechanism in
  `instructions/memory.instructions.md` doesn't depend on being remembered unprompted
- `vite-env-guard` — **blocks** writes putting a secret-looking value behind a `VITE_` prefix
  (everything `VITE_`-prefixed is compiled into the public client bundle)
- `native-dialog-guard` — **blocks** writing `window.confirm` / `alert` / `prompt` into a Power Apps
  Code App, where the iframe sandbox makes `confirm()` return `false` without ever showing a dialog
- `branch-guard` — warns at session start when you are on a protected branch with uncommitted work
- `project-context-check` — raises a gate at session start while `project-context.md` is still the
  unfilled template, so `/setup` does not depend on someone remembering it exists
- `lint-fix-on-edit` — runs `eslint --fix` on each file the agent writes, so the next read sees
  corrected code instead of drift accumulating until session end
- `dataverse-schema-drift` — warns at session start when `power.config.json` is newer than
  `src/generated/`, the one failure mode no build or typecheck can see

**Which event you pick determines what's possible.** `preToolUse` stdout is *parsed* — it can deny a
call and give Copilot the reason. `sessionStart` stdout is *parsed* — `additionalContext` is injected
into the session. `postToolUse` stdout is **ignored**, so hooks on that event must *fix* things, not
report them. See the table in `instructions/hooks.instructions.md`.

## 🔍 How Copilot Uses These Files — Context Loading Hierarchy

1. **Always loaded:** `copilot-instructions.md`
2. **Conditionally loaded (file pattern match):** instructions matching the current file's `applyTo`
3. **On-demand (explicit invocation):** agents via the picker dropdown, prompts via `/name`, skills when triggered
4. **Deterministic (event-driven):** hooks, independent of what the model decides to load

**Example — editing `App.tsx`:** `copilot-instructions.md` loads, plus the `**` files
(`general-coding`, `context-engineering`, `memory`) and the `.tsx` matches (`react-ts`, `shadcn-ui`,
`data-fetching`, `forms-and-validation`, `error-handling`, `a11y`, `performance-optimization`, and
`power-apps-code-apps` in a Code App). **Measured 2026-09-26: about 71KB (~18k tokens) in a Code App,
about 52KB in a plain `react-vite` project** — `power-apps-code-apps` alone is the difference. The
`docs/reference/` catalogues, every agent and every prompt stay out of context until invoked, and
`csharp-dotnet` / `dataverse-plugins` until a `.cs` file is in play.

Measure it rather than assuming — the `applyTo` globs are the only source of truth, and this is
exactly where the baseline drifted before. This section said "roughly 30KB" until the figure above
was actually measured.

## 📝 Best Practices

1. **Keep core files minimal** — `copilot-instructions.md` short and factual; reference detail
   instead of inlining it.
2. **Scope `applyTo` narrowly** — broad instruction files should be short; long reference material
   should have a narrow `applyTo` or be invoked on-demand (agent/prompt/skill) instead.
3. **Reference, don't repeat** — point at another file rather than duplicating its content.
4. **Be specific and actionable** — "Validate all user inputs before processing," not "consider
   security when appropriate."

## 🔄 Maintenance

- **`GOVERNANCE_MATRIX.md` is generated** — run `pwsh ./tools/generate-governance-matrix.ps1` after
  adding or removing an asset. Never edit it by hand; it drifted to ~25% accurate when it was
  hand-maintained, and a registry that stale is worse than none because it gets trusted.
- **Run `pwsh ./tools/lint-baseline.ps1` after any frontmatter change.** It catches missing/broken
  `applyTo`, prompts pointing at non-existent agents, skill name/folder mismatches, dangling hook
  script paths, unconfigured MCP tool references, profile patterns matching nothing, and a stale
  governance matrix. Errors mean something is genuinely broken.
- When adding a new agent/instruction/prompt/skill/hook, follow the conventions in the matching
  `instructions/*.instructions.md` meta-guide, add it to the right profile in
  `tools/baseline-profiles.json`, then regenerate the matrix.
- Review periodically for: context bloat (files that grew past their stated size), broken
  cross-references, and instructions whose `applyTo` has drifted too broad.

## 📚 Additional Resources

- [Progressive Disclosure Pattern](./PROGRESSIVE_DISCLOSURE.md) — full rationale
- [GitHub Copilot Docs](https://docs.github.com/en/copilot) — official documentation
- [Awesome Copilot](https://github.com/github/awesome-copilot) — community catalog. Worth browsing,
  but see `AGENTS.md`: adapt anything borrowed, never vendor it wholesale.

---

**Last Updated:** 2026-09-26
