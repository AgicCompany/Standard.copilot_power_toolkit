# Governance Matrix

> **Generated file — do not edit by hand.** Regenerate with
> `pwsh ./tools/generate-governance-matrix.ps1` after adding or removing a baseline asset.
> `lint-baseline.ps1` fails if this file is out of date.

"Profiles" is which `tools/baseline-profiles.json` profiles copy the asset into a target
project. `all` = every profile. `full only` = kept in the baseline but shipped only by the
catch-all `full` profile.

## Instructions

| Asset | Auto-applies to | Profiles |
|---|---|---|
| `instructions/a11y.instructions.md` | `**/*.{tsx,jsx}` | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `instructions/agent-safety.instructions.md` | `**/agents/**, **/mcp-server/**, **/*.agent.ts, **/tools/**/*.ts` | baseline-authoring |
| `instructions/agent-skills.instructions.md` | `**/skills/**/SKILL.md` | baseline-authoring |
| `instructions/agents.instructions.md` | `**/*.agent.md` | baseline-authoring |
| `instructions/context-engineering.instructions.md` | `**` | all |
| `instructions/csharp-dotnet.instructions.md` | `**/*.cs,**/*.csproj,**/*.sln` | power-apps-canvas-migration, power-apps-code-app |
| `instructions/data-fetching.instructions.md` | `**/*.{ts,tsx}` | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `instructions/dataverse-plugins.instructions.md` | `**/*.cs` | power-apps-canvas-migration, power-apps-code-app |
| `instructions/devops-core-principles.instructions.md` | _on-demand (no applyTo)_ | power-apps-canvas-migration, power-apps-code-app |
| `instructions/error-handling.instructions.md` | `**/*.{ts,tsx}` | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `instructions/fluent-ui-v9.instructions.md` | `**/*.{tsx,jsx}` | full only |
| `instructions/forms-and-validation.instructions.md` | `**/*.{ts,tsx}` | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `instructions/general-coding.instructions.md` | `**` | all |
| `instructions/git.instructions.md` | _on-demand (no applyTo)_ | all |
| `instructions/gitflow.instructions.md` | _on-demand (no applyTo)_ | all |
| `instructions/github-actions.instructions.md` | `.github/workflows/**/*.{yml,yaml}` | all |
| `instructions/hooks.instructions.md` | `.github/hooks/**, hooks/**` | baseline-authoring |
| `instructions/instructions.instructions.md` | `**/*.instructions.md` | baseline-authoring |
| `instructions/memory.instructions.md` | `**` | all |
| `instructions/performance-optimization.instructions.md` | `**/*.{tsx,jsx}` | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `instructions/playwright-typescript.instructions.md` | `**/tests/**/*.spec.ts, **/e2e/**/*.spec.ts, playwright.config.ts` | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `instructions/power-apps-canvas-yaml.instructions.md` | `**/*.pa.yaml, **/*.fx.yaml` | power-apps-canvas-migration |
| `instructions/power-apps-code-apps.instructions.md` | `**/*.{ts,tsx}, **/power.config.json, **/vite.config.*, **/package.json` | power-apps-canvas-migration, power-apps-code-app |
| `instructions/power-platform-mcp-development.instructions.md` | `**/connectors/**/*.{json,csx}, **/apiDefinition*.json, **/apiProperties*.json, **/*.csx` | full only |
| `instructions/prompt.instructions.md` | `**/*.prompt.md` | baseline-authoring |
| `instructions/react-ts.instructions.md` | `**/*.{ts,tsx}` | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `instructions/shadcn-ui.instructions.md` | `**/*.{tsx,jsx}` | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `instructions/tailwind-v4-vite.instructions.md` | `**/vite.config.*, **/*.css` | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `instructions/typescript-mcp-server.instructions.md` | `**/mcp-server/**/*.ts, **/mcp-servers/**/*.ts, **/src/mcp/**/*.ts, **/*.mcp.ts` | full only |
| `instructions/vite-env-and-secrets.instructions.md` | `**/*.env, **/*.env.*, **/vite.config.*, **/vite-env.d.ts` | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `instructions/vitest-react-testing.instructions.md` | `**/*.test.ts, **/*.test.tsx, **/vitest.config.*, **/vitest.setup.*` | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `instructions/work-items.instructions.md` | _on-demand (no applyTo)_ | power-apps-canvas-migration, power-apps-code-app |

## Agents

| Asset | Description | Profiles |
|---|---|---|
| `agents/accessibility.agent.md` | Expert assistant for web accessibility (WCAG 2.1/2.2), inclusive UX, and a11y testing | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `agents/canvas-migration-guide.agent.md` | Canvas to React migration specialist for formula translation, component refactoring, and parity validation | power-apps-canvas-migration |
| `agents/checklist.agent.md` | Code review checklist validation for structure, standards, and quality gates | baseline-authoring, power-apps-canvas-migration, power-apps-code-app, react-vite |
| `agents/dataverse-expert.agent.md` | Dataverse specialist for schema design, query shape, concurrency, and the specific limits of Power Apps CLI... | power-apps-canvas-migration, power-apps-code-app |
| `agents/debug.agent.md` | Debug your application to find and fix a bug | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `agents/delivery.agent.md` | Git delivery workflow — creates the feature branch before work starts, writes conventional commits, and ope... | all |
| `agents/devops.agent.md` | DevSecOps Engineer expert specializing in Microsoft ecosystem security, automation, and compliance best pra... | power-apps-canvas-migration, power-apps-code-app |
| `agents/lyra.agent.md` | Lyra - AI Prompt Optimization Specialist | baseline-authoring |
| `agents/parity-auditor.agent.md` | Canvas↔React parity auditor for systematic feature comparison, gap detection, and acceptance criteria | power-apps-canvas-migration |
| `agents/plan.agent.md` | Strategic planning and architecture assistant focused on thoughtful analysis before implementation. Helps d... | all |
| `agents/power-platform-expert.agent.md` | Power Platform expert providing guidance on Code Apps, canvas apps, Dataverse, connectors, and Power Platfo... | power-apps-canvas-migration, power-apps-code-app |
| `agents/prd.agent.md` | PRD Assistant that helps you write Product Requirements Documents (PRDs) with clarity and precision | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `agents/repo-architect.agent.md` | Bootstraps and validates agentic project structures for GitHub Copilot (VS Code) and OpenCode CLI workflows... | baseline-authoring |
| `agents/review.agent.md` | Comprehensive code review with detailed feedback, suggestions, and improvement recommendations | all |
| `agents/small-plan.agent.md` | Lightweight plan generator that produces a fixed 4-section plan (Overview, Requirements, Steps, Testing) fo... | all |
| `agents/tdd.agent.md` | Test-Driven Development (TDD) assistant that enforces writing tests before implementation | baseline-authoring, power-apps-canvas-migration, power-apps-code-app, react-vite |

## Prompts

| Asset | Description | Profiles |
|---|---|---|
| `prompts/ado-pipelines.prompt.md` | Instructions for expert DevSecOps Engineers specializing in Azure DevOps pipeline design and configuration | power-apps-canvas-migration, power-apps-code-app |
| `prompts/code-review-checklist.prompt.md` | Comprehensive code review checklist for maintaining high code quality standards | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `prompts/code-review.prompt.md` | Comprehensive code review checklist | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `prompts/create-prd.it.prompt.md` | Generazione di un Product Requirements Document (PRD) in formato Markdown | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `prompts/create-prd.prompt.md` | Generating a Product Requirements Document (PRD) in Markdown format | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `prompts/devops.prompt.md` | DevOps and DevSecOps expert for Microsoft ecosystem, Git workflows, and best practices | power-apps-canvas-migration, power-apps-code-app |
| `prompts/e2e-test.prompt.md` | Generate complete end-to-end tests using Playwright in TypeScript | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `prompts/generate-tasks.it.prompt.md` | Generating a task list from an existing Product Requirements Document (PRD) | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `prompts/generate-tasks.prompt.md` | Generating a task list from an existing Product Requirements Document (PRD) | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `prompts/git.prompt.md` | Instructions for managing Git commits and branches in the project. | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `prompts/migration-slice.prompt.md` | Bilingual migration slice prompt (EN/IT) from Canvas to React with strict acceptance criteria | power-apps-canvas-migration |
| `prompts/new-chat-bootstrap.prompt.md` | Resume work in a new chat — loads project context and durable memory, then proposes the next smallest slice. | all |
| `prompts/parity-audit.prompt.md` | Bilingual parity audit (EN/IT) between legacy Canvas behavior and React implementation for a scoped feature | power-apps-canvas-migration |
| `prompts/process-task-list.it.prompt.md` | Gestione della Task List in file markdown per monitorare i progressi nel completamento di un PRD | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `prompts/process-task-list.prompt.md` | Manage the task list in a markdown file to track progress toward completing a PRD | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `prompts/session-kickoff.prompt.md` | Bilingual session kickoff template (EN/IT) for high-signal Copilot collaboration | all |
| `prompts/setup.prompt.md` | Project initialization and copilot-instructions.md setup | all |

## Skills

| Asset | Description | Profiles |
|---|---|---|
| `skills/agent-governance/SKILL.md` | \| | baseline-authoring |
| `skills/agentic-eval/SKILL.md` | \| | baseline-authoring |
| `skills/appinsights-instrumentation/SKILL.md` | Automates the integration of Azure Application Insights telemetry into web applications for monitoring, dia... | power-apps-canvas-migration, power-apps-code-app |
| `skills/code-app-deploy/SKILL.md` | TRIGGER - read this BEFORE running any CLI command that writes to an environment, especially pa app push, a... | power-apps-canvas-migration, power-apps-code-app |
| `skills/component-scaffold/SKILL.md` | TRIGGER - read this BEFORE writing the first line of any new React component, and before creating any file ... | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `skills/custom-api-authoring/SKILL.md` | TRIGGER - read this BEFORE writing any handler that changes more than one Dataverse row in a single user ac... | power-apps-canvas-migration, power-apps-code-app |
| `skills/dataverse-schema-validator/SKILL.md` | Validate entity relationships, required fields, option sets against power.config.json—catch schema drift be... | power-apps-canvas-migration, power-apps-code-app |
| `skills/dataverse-typed-client/SKILL.md` | TRIGGER - read this BEFORE writing any code that reads or writes Dataverse: before the first call to a gene... | power-apps-canvas-migration, power-apps-code-app |
| `skills/frontend-design/SKILL.md` | Create production-grade, distinctive frontend interfaces with modern UX/UI patterns for web applications | power-apps-canvas-migration, power-apps-code-app, react-vite |
| `skills/lock-semantics-expert/SKILL.md` | Reusable patterns for optimistic locking, conflict resolution, retry logic, and concurrent data safety | power-apps-canvas-migration, power-apps-code-app |
| `skills/mcp-builder/SKILL.md` | Build Model Context Protocol (MCP) servers to extend GitHub Copilot and AI agents with custom tools and dat... | baseline-authoring |
| `skills/power-apps-code-app-scaffold/SKILL.md` | Power Apps CLI walkthrough for Power Apps Code Apps — auth, project init, and connecting Dataverse tables a... | power-apps-canvas-migration, power-apps-code-app |

## Hooks

| Asset | Description | Profiles |
|---|---|---|
| `hooks/branch-guard.json` | Warns at session start when you are sitting on a protected branch with uncommitted work, before that work becomes expensive to move | all |
| `hooks/build-gate.json` | Runs TypeScript type-checking and lint (if configured) at session end so a session cannot quietly end with a broken build | all |
| `hooks/dataverse-schema-drift.json` | Warns at session start when power.config.json is newer than the Power Apps CLI generated services, since stale generated code fails at runtime, not build time | all |
| `hooks/dependency-license-checker.json` | Scans newly added dependencies for license compliance (GPL, AGPL, etc.) at session end | all |
| `hooks/governance-audit.json` | Scans Copilot agent prompts for threat signals and logs governance events | all |
| `hooks/lint-fix-on-edit.json` | Runs eslint --fix (and optionally prettier) on each file the agent writes, so the next read sees corrected code instead of accumulating drift until session end | all |
| `hooks/memory-reminder.json` | Prints a short reminder at session start pointing to .github/docs/project-memory.md, so the memory mechanism does not depend on being remembered unprompted | all |
| `hooks/native-dialog-guard.json` | Blocks writing window.confirm / alert / prompt into a Power Apps Code App, where the iframe sandbox makes confirm() return false without ever showing a dialog | all |
| `hooks/project-context-check.json` | Raises a gate at session start when project-context.md is still the unfilled template, so the /setup mechanism does not depend on someone remembering it exists | all |
| `hooks/secrets-scanner.json` | Scans files modified during a Copilot coding agent session for leaked secrets, credentials, and sensitive data | all |
| `hooks/session-logger.json` | Logs metadata when Copilot sessions start, each turn completes, and a prompt is submitted - timestamps, working directory and event names; no prompt text and no tool calls | all |
| `hooks/tool-guardian.json` | Blocks dangerous tool operations (destructive file ops, force pushes, DB drops) before the Copilot coding agent executes them | all |
| `hooks/vite-env-guard.json` | Blocks writes that put a secret-looking value behind a VITE_ prefix, because everything VITE_-prefixed is compiled into the client bundle and is public | all |

## Policies

| Asset | Purpose |
|---|---|
| `SAFETY_GUARDRAILS.md` | Blocked actions, confirmation-required actions, secret handling |
| `docs/WORKFLOW_AUTHORITY.md` | Canonical branching/release model (Gitflow) |
| `docs/mcp-servers.md` | MCP server config and known gaps |
| `.github/docs/project-memory.md` | Cross-session durable memory store, in a project. Seeded once from `docs/project-memory.template.md`, then project-owned |

