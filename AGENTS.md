# AGENTS.md

## What This Repository Is

`.github_general` is a reusable baseline of GitHub Copilot / agentic-coding configuration. It is
**not** a product repo — there is no build step, and the only CI is a lint and hook-probe workflow
that checks this repository itself. It is meant to live outside project repos and be copied into
each new project as that project's `.github/` folder.

- Source template: this folder (`.github_general`)
- Target in each project: `.github/`
- Copy mechanism: `tools/apply-baseline.ps1` (see `USAGE_APPLY_ANY_PROJECT.md`)

**Profiles.** `apply-baseline.ps1` is driven by `tools/baseline-profiles.json`. A profile decides
what gets *copied* into a target project. **An asset in no profile ships to nobody** except through
the `full` escape hatch — so in a released baseline it is dead weight that still looks maintained.
Give an asset a profile once it has been tested in real use; until then it does not belong here.
New project types are covered by **adding a profile**, not by accumulating unassigned assets.

The deliberate exception is the two MCP-authoring instructions (`typescript-mcp-server`,
`power-platform-mcp-development`): kept, reachable through `full`, until an MCP profile has been
earned by building one. They are why the linter reports two "belongs to no profile" warnings.

| Profile | For |
|---|---|
| `react-vite` | React + TypeScript + Vite web app (Tailwind v4 + shadcn/ui, TanStack Query, Vitest) |
| `power-apps-code-app` | extends `react-vite` + Dataverse, Power Platform, Canvas parity — **the default** |
| `baseline-authoring` | working on this baseline itself, or another Copilot config repo |
| `full` | everything; escape hatch preserving the pre-profile behaviour |

`pwsh ./tools/apply-baseline.ps1 -ListProfiles` prints them. `-DryRun` shows what a run would do.
`-Prune` removes baseline-owned files a profile no longer includes (it only ever touches paths that
exist in this baseline, so project-authored files are safe).

**`copilot-instructions.md` and `project-context.md` are project-owned.** They are seeded once from
their `.template.md` counterparts and never overwritten again, including under `-Force`. Do not
"fix" that guard — the previous version checked the baseline folder for a file that only ever exists
in the target, so a `-Force` re-sync silently replaced a project's tailored instructions with the
generic template.

This file itself is **excluded** from that copy (along with `tools/`, `docs/examples/`, and
`USAGE_APPLY_ANY_PROJECT.md`) — it documents the baseline repo for whoever maintains it, not the
target project. A target project's own stack assumptions (e.g. "React + TypeScript + Vite") belong
in `copilot-instructions.template.md`, which *is* copied and becomes the target's always-loaded
`.github/copilot-instructions.md`.

Everything in here is organized around **progressive disclosure**: a small always-loaded core, plus
detail loaded only when relevant. See `PROGRESSIVE_DISCLOSURE.md` and `QUICK_REFERENCE.md` for the
full rationale before adding new root-level or always-applying content.

## Repository Structure

```
.
├── copilot-instructions.template.md   # Fills target's .github/copilot-instructions.md
├── project-context.template.md        # Fills target's .github/project-context.md
├── GOVERNANCE_MATRIX.md                # Registry of active baseline assets
├── SAFETY_GUARDRAILS.md                # Baseline safety/confirmation policy
├── .vscode/mcp.json # MCP server config — lands at TARGET PROJECT ROOT, not under .github/
├── agents/          # Copilot custom agents (*.agent.md), selected in the picker (NOT @name)
├── instructions/    # Auto-applied guidance by file pattern (*.instructions.md)
├── prompts/         # On-demand slash-command templates (*.prompt.md)
├── skills/          # Bundled task skills, folder + SKILL.md
├── hooks/           # Session-lifecycle automation, FLAT {name}.json + {name}.README.md + scripts/
├── docs/            # Runbooks, workflow authority, mcp-servers.md, project-memory.template.md, and
│                    # docs/examples/ (not copied to targets)
├── tools/           # apply-baseline.ps1, lint-baseline.ps1 (not copied to targets)
└── ISSUE_TEMPLATE/  # GitHub issue templates carried into target projects
```

## Governance Files

- `GOVERNANCE_MATRIX.md` — tracks which baseline assets are active and why. Update it whenever a
  baseline asset (instruction/prompt/agent/skill/policy) is added or removed.
- `SAFETY_GUARDRAILS.md` — blocked actions, confirmation-required actions, secret handling.
- `docs/WORKFLOW_AUTHORITY.md` — the canonical branching/release model (Gitflow) for repos using
  this baseline; other workflow docs defer to it unless explicitly overridden per-project.

## File Type Conventions

### Agents (`agents/{role}.agent.md`)
- Frontmatter: `description` (required), `name` (optional — the invocation slug; **defaults to the
  filename** if omitted, so keep filenames lowercase-hyphenated and matching whatever slug you want),
  `tools`, `model` (optional), `target` (optional: `vscode` | `github-copilot`).
- There is no `agent:` frontmatter field — it is not part of the real schema and is silently
  ignored. An earlier version of this baseline had ten agent files using `agent: <slug>` under the
  mistaken belief it set the invocation name; it does nothing. Verified against
  https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/create-custom-agents.
- Selected via the **agent/mode picker dropdown** in Copilot Chat (same control used for Ask/Edit/Agent
  modes), or by typing `/agents` to open the picker. **There is no `@mention` invocation** — typing
  `@name` in the chat input does not select the agent. Confirmed empirically: typing `@small-plan`
  resolved to VS Code's generic file-reference autocomplete (`@file:small-plan.agent.md`, attaching
  the raw file as context) rather than switching to the agent. Docs pages disagree/are ambiguous on
  this; trust the dropdown behavior over any `@name` convention written elsewhere.
- If you set `name` explicitly, make it a plain slug (`plan`, not `"Plan Mode - Strategic Planning &
  Architecture"`) — it's literally what's shown in the picker list, not just an internal ID.

### Instructions (`instructions/{topic}.instructions.md`)
- Frontmatter: `description` (required), `applyTo` (glob pattern(s) of files it auto-applies to).
- **Omitting `applyTo` means the file never loads.** Per the VS Code docs: *"If not specified, the
  instructions are not applied automatically, but you can still add them manually to a chat
  request."* Five files in this baseline once had no `applyTo` — including `general-coding`, which
  the README described as "always relevant" while it was in fact loading nowhere. If a file has no
  natural file-pattern trigger (git workflow, ADO work items, DevOps culture), that is a legitimate
  on-demand choice, but it must be **declared with a `LOADING:` or `OPT-IN:` note in the body** and
  its operative rules duplicated into `copilot-instructions.template.md`, which *is* always loaded.
  `lint-baseline.ps1` errors on an undeclared missing `applyTo`.
- `applyTo: '*'` (single star) matches only root-level files — it is not a recursive glob. This was
  a real bug in `devops-core-principles`. The linter errors on it.
- Keep `applyTo` as narrow as the guidance actually is. Anything scoped `applyTo: '**'` loads into
  *every* Copilot session touching *any* file in the target project — reserve that scope for genuinely
  universal, short guidance, not large reference catalogs.
- **Narrowing `applyTo` has a cost: restate preconditions in the file that actually loads.** A
  narrow glob is right for keeping context small, but it means setup guidance is absent exactly when
  the model is doing the work. Found live: `tailwind-v4-vite.instructions.md` is scoped to
  `vite.config.*` / `*.css`, so during a `.tsx` edit nothing said "check Tailwind is installed" —
  Copilot wrote `bg-primary` classes and a `cn()` helper into a project with no Tailwind. It built,
  type-checked, and passed 7 tests while rendering unstyled, because class names are just strings.
  Whenever instruction A depends on setup described in instruction B, and their globs don't overlap,
  A must carry the precondition check itself.
- **Large reference material does not belong in `instructions/`.** Three files (a11y, performance,
  power-apps-code-apps) had grown to 25-28KB each and all auto-applied to `**/*.tsx`, putting ~97KB
  (~25k tokens) of prose into every component edit — the opposite of the progressive disclosure this
  baseline claims. The pattern now is: a short instruction file carrying the rules that change code,
  plus the full catalogue in `docs/reference/`, linked from it and read on demand.

### Prompts (`prompts/{action}.prompt.md`)
- Frontmatter: `description`, optionally `agent`. Invoked on-demand via slash command.

### Skills (`skills/{name}/SKILL.md`)
- Frontmatter: `name` (matches folder name), `description`. Loaded in full when triggered, so treat
  size as a real cost even though loading is on-demand.
- **A skill must tell the reader to CHECK a precondition, never assume it.** This is the single most
  common defect found in the 2026-08 acceptance run — five separate instances, all the same shape: a
  step that describes the world instead of asking the reader to look at it.

  | What the skill said | What was actually true |
  |---|---|
  | run `pnpm typecheck` and `pnpm test` | the scaffold defines neither; each is a stop-on-failure gate, so the deploy halted at step 2 |
  | *write* `pnpm-workspace.yaml` | pnpm already wrote it, with placeholder values to edit |
  | instrument with the Node `applicationinsights` package | a Code App is browser-only; that package cannot run there |
  | the generated service is missing a field → regenerate | the generator emits full metadata; the field was always there |
  | add the exception to the hook's `env` block | needs a host reload, and the next `-Force` sync erases it |

  Every one compiled, built, linted or exited zero while being wrong. Write the check into the step:
  *"read `package.json` and run only the scripts it defines"*, not *"run `pnpm test`"*. Prefer
  **"verify X, then do Y"** over **"do Y (X is usually true)"**.
- **Say where the authority is.** When a value can be looked up — a CLI flag, a generated file, a
  config key — name the command or file that settles it rather than restating it from memory. Guessed
  CLI aliases have cost this baseline four tool calls in one run and a silent no-op in another.

### Hooks (`hooks/{name}.json` + `hooks/{name}.README.md` + `hooks/scripts/`)
- **Flat only** — `{name}.json` (config: which event, `bash`/`powershell` script paths, `env`) and
  `{name}.README.md` (frontmatter: `name`, `description`, optional `tags`) sit directly in `hooks/`,
  never in a per-hook subfolder. Scripts live in the shared `hooks/scripts/` folder.
- This is confirmed, not a style preference: GitHub Copilot's hook discovery only scans flat
  `.github/hooks/*.json` — it does not recurse into subfolders. An earlier version of this baseline
  used `hooks/{name}/hooks.json`, which meant the host could never find any hook, ever, regardless of
  whether the script itself was correct. Verified against the authoritative hooks reference.
- Every hook should declare both `bash` and `powershell` script paths — a Windows host without bash
  on PATH gets nothing from a bash-only hook, silently, no error.

### Plugins
- Not currently used in this baseline. If reintroduced, a plugin must actually reference files that
  exist in this repo — do not carry over plugin manifests from other marketplaces/collections without
  rewriting their paths, author, and install instructions for this repo.

### MCP Servers (`.vscode/mcp.json`)
- Several agents' `tools:` lists only work if the matching MCP server is configured here. Tool
  references must be `server-name/*` or `server-name/tool-id` — a bare name with no `/` does not
  resolve to an MCP tool and is silently dropped by VS Code, no error. See `docs/mcp-servers.md` for
  what's configured, what's a known-documented gap, and how to add a new server.
- **Pin every locally launched server to an exact version, never `@latest`.** These start
  automatically on every developer's machine; `@latest` lets a vendor ship an unreviewed build —
  including a prerelease — into every project. `docs/mcp-servers.md` has the bump procedure.
- This file lives outside `.github/` on purpose (VS Code only reads workspace MCP config from
  `.vscode/mcp.json` at the project root) — `tools/apply-baseline.ps1` places it there specially.

### Memory (`.github/docs/project-memory.md` in a project)
- Copilot has no built-in persistent memory. `instructions/memory.instructions.md` makes the concept
  real by pointing at this concrete file and telling agents to read it before non-trivial work and
  append durable facts/corrections to it. If you touch the memory instructions, keep them pointing at
  an actual file — prose about "storing memory" with no defined location is a no-op.

## Deciding Where a Rule Belongs

Before writing a new rule, classify it. This was arrived at the hard way — a Tailwind precondition
was rewritten three times as prose and failed to bind in six separate contexts (direct prompt,
planning, TDD, refactor, checklist review, code review) before being made a mechanical check.

| The rule is... | Put it in | Why |
|---|---|---|
| Mechanically checkable, no judgement | a **hook** (`preToolUse` to block, `build-gate` to report) | Deterministic. Prose competes with the model's priors; a hook does not. |
| A judgement call needing context | an **instruction** with a narrow `applyTo` | Loads deterministically by glob, still leaves room to think |
| A long walkthrough | a **skill**, with a TRIGGER-shaped description | On-demand, but loading is discretionary — see `agent-skills.instructions.md` |
| Reference material | `docs/reference/`, linked from a short instruction | Never auto-loaded; no context cost |

**Before writing a rule, ask what the model will do *instead* — and name that too.** Every
instruction failure found in live testing was this, not disobedience: the rule closed one door and
the model walked through an unnamed one.

| Rule as written | What it did instead |
|---|---|
| "never hand-write a shadcn component" | used `window.confirm` — a native API, not a component |
| "install it, don't approximate" | hand-wrote the component when the CLI errored — no escape path was defined |
| "don't add Redux **without asking**" | installed it when asked — the wording reads as "unless requested" |
| "append durable facts to `docs/project-memory.md`" | wrote to Copilot's built-in memory tool instead |

Write the prohibition **and** the alternative path: what to do when the sanctioned route is blocked,
which competing mechanism not to use, and what "ask first" concretely means. A rule with an unnamed
escape hatch is a rule with a default.

Two more rules of thumb from the same testing:

- **Pair every absolute with an obligation the model can always meet.** "Always write a colocated
  test" can be silently declined. "…and if you deliberately skip it, name which and why" cannot —
  saying so is always possible, and it converts a silent omission into a visible decision the user
  can act on. Silent omission, not incompleteness, is the failure mode.
- **State the consequence, not just the rule.** "Check Tailwind is installed" is ignorable. "These
  classes compile, type-check, lint, build and pass every test while rendering nothing" explains why
  it cannot be deferred.

## Adding a New Baseline Asset

1. Create the file/folder following the conventions above.
2. **Name the condition under which it applies, then ask whether that condition is a property of the
   platform or of one project.** A baseline asset must be *conditionally universal*: it applies any
   time you work on that stack and its condition is satisfied. Reusability is not the test —
   plenty of project-specific material is reusable in theory and never fires in practice.

   | Condition | Verdict |
   |---|---|
   | "the project writes more than one Dataverse row in one action" | **In.** Any Code App can hit this |
   | "the project has a plug-in assembly" | **In.** Gated, but the gate is a platform fact |
   | "the project stores its documents in SharePoint" | **Out.** That is an integration choice, not a Code App condition — it belongs in that project's own `.github/` |

   Rejected on 2026-09-24 by exactly this test: a SharePoint document-store reference for the
   `power-apps-code-app` profile. SharePoint is not wrong, and it is not rare; it is simply not a
   condition of using Code Apps.
3. **Make the asset declare that condition where the model will actually see it** — `applyTo` for an
   instruction, `TRIGGER`/`SKIP` for a skill, and an opening paragraph that hands off to the right
   file when the condition does not hold. An asset whose condition is only in the author's head
   either loads everywhere or never binds.
4. Confirm nothing in it identifies a real client, project, or schema (see *Working In This Repo*).
5. Add an entry to `GOVERNANCE_MATRIX.md` — or regenerate it with
   `pwsh ./tools/generate-governance-matrix.ps1`, which the linter checks.
6. If it's large, reference-heavy material, prefer putting the bulk in `docs/` and keeping the
   `instructions/`/`agent/`/`skill` file itself short and pointing at it.

## Working In This Repo

- There's no build step, but there is a self-check: `pwsh ./tools/lint-baseline.ps1`. Run it after
  editing any agent/instruction/hook/skill frontmatter or MCP config — it catches the bad-`agent:`-field
  class of bug, dangling hook script paths, invalid hooks.json, and unconfigured MCP tool references.
  It's advisory (warnings don't fail it), but errors mean something is genuinely broken.
- Do not copy content from other "awesome-copilot"-style catalogs/marketplaces wholesale. Past
  instances of that (an old `AGENTS.md`, `docs/README.*.md` catalog dumps, a broken `plugins/`
  manifest) referenced files, commands, and processes that don't exist in this repo and have since
  been removed. Adapt anything borrowed from elsewhere before committing it here.
- Keep `copilot-instructions.template.md` and `project-context.template.md` generic. **Never fill
  them in with a real project's specifics and leave that at the baseline root.** This has happened:
  a filled-in `copilot-instructions.md` naming one client project's stack and domain sat at the root,
  so `apply-baseline.ps1` copied that project's context into every new project instead of falling
  back to the generic template.
- **Nothing identifying a real client, project, or schema belongs in this repository.** Not as an
  example, not as a worked reference, not in a session log. It leaks into every project the baseline
  is applied to — `common` assets land in all of them — and into the git history permanently.
  Genericise domain terms (`Request`, `Commitment`, `Asset`) when illustrating a pattern.

---

**Maintainers:** Keep this file accurate to what's actually in the repo. If a section describes
tooling, files, or workflows that don't exist here, fix or remove it rather than leaving it aspirational.
