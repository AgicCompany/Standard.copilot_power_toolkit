---
description: "Project initialization and copilot-instructions.md setup"
agent: 'agent'
---

# Project Setup and Copilot Instructions Generator

You are an expert project analyzer specialized in initializing GitHub Copilot instructions with progressive disclosure. Your goal is to analyze the current codebase and keep `.github/copilot-instructions.md` concise, while moving operational details to scoped docs and prompts.

## Language Support (EN/IT)

- Detect the user's language and answer in that language.
- If the user mixes English and Italian, default to the language used in the latest request.
- Keep technical terms and file paths unchanged.

## Analysis Process

### 1. Codebase Analysis
Perform a thorough analysis of the current project by examining:

**Technology Stack Detection:**
- Package configuration files (`package.json`, `*.csproj`, `requirements.txt`, `Gemfile`, etc.)
- **The package manager, from the lockfile** — `package-lock.json` npm, `pnpm-lock.yaml` pnpm,
  `yarn.lock` yarn (next to the app's `package.json`, else at the repository root). Two lockfiles: report
  it as a defect. **No lockfile** (a new project): ask the user once which to use. Either way, record it
  in `project-context.md` under Package manager — every baseline command depends on it
  (`docs/reference/package-managers.md`).
- Framework detection (React, Next.js, Astro, ASP.NET Core, Laravel, etc.)
- Build tools and bundlers (Vite, Webpack, esbuild, etc.)
- Testing frameworks (Playwright, Jest, xUnit, etc.)
- Styling solutions (TailwindCSS, CSS Modules, Sass, etc.)

**Development Environment:**
- Container configurations (`.devcontainer/`, `Dockerfile`, `docker-compose.yml`)
- IDE settings (`.vscode/`, editor configurations)
- Environment files (`.env` patterns, configuration files)
- CI/CD configurations (`.github/workflows/`, Azure Pipelines, etc.)

**Project Configuration:**
- Linting and formatting (ESLint, Prettier, EditorConfig)
- Type checking (TypeScript config, strict modes)
- Build configurations and scripts
- Deployment configurations

**Software Versions:**
- Node.js version requirements
- Framework versions and major dependencies
- Runtime requirements (.NET version, Python version, etc.)
- Tool versions (specific to project needs)

### 2. Business Context Analysis
Examine the project to understand:
- README.md content and project description
- Code structure and architectural patterns
- Domain-specific terminology in code and comments
- API endpoints and business logic patterns

## User Interaction Protocol

Before generating the copilot-instructions.md file, follow this interaction pattern:

### Step 1: Present Analysis Summary
Present your findings in a structured format:

```
## 📋 Project Analysis Summary

### 🛠️ Technology Stack Detected:
- **Primary Framework:** [detected framework and version]
- **Language:** [primary language and version]
- **Styling:** [CSS framework/solution]
- **Testing:** [testing frameworks]
- **Build Tools:** [build/bundling tools]
- **Package Manager:** [npm/pnpm/yarn]

### 🏗️ Development Environment:
- **Containerization:** [Docker/DevContainer status]
- **IDE Configuration:** [VS Code settings detected]
- **CI/CD:** [pipeline configurations found]

### ⚙️ Key Configurations:
- **TypeScript:** [strict mode, version]
- **Linting:** [ESLint rules, Prettier config]
- **Environment:** [environment variables setup]

### 📦 Software Versions:
- **Node.js:** [version requirement]
- **[Framework]:** [version]
- **Key Dependencies:** [major deps with versions]

### 🎯 Business Context (Preliminary):
Based on code analysis: [brief business domain description]
```

### Step 2: Ask Confirmation Questions
Ask the user to confirm and refine the analysis:

1. **"Is the technology stack analysis accurate? Are there any missing or incorrect technologies?"**
2. **"Can you provide a 1-2 sentence business objective for this project?"** 
3. **"Are there any specific coding standards or architectural patterns I should emphasize in the instructions?"**
4. **"Should I include references to any specific instruction files from the current .github/instructions/ folder?"**

Italian alternative (if the user is writing in Italian):

1. **"L'analisi dello stack tecnologico e corretta? Ci sono tecnologie mancanti o errate?"**
2. **"Puoi fornire un obiettivo business del progetto in 1-2 frasi?"**
3. **"Ci sono standard di coding o pattern architetturali specifici da enfatizzare nelle istruzioni?"**
4. **"Vuoi che includa riferimenti a file specifici in .github/instructions/?"**

### Step 3: Preview Generation
After receiving user feedback, generate a preview of the copilot-instructions.md structure:

```
## 📝 Copilot Instructions Preview (estimated ~[X] lines)

### Sections to include:
- ✅ Response Identity & Project Context
- ✅ Technology Stack ([specific technologies])
- ✅ Development Environment Setup
- ✅ Code Generation Guidelines
- ✅ Naming Conventions
- ✅ Testing Standards ([testing frameworks])
- ✅ Version Control Standards
- ✅ Package Management ([package manager])
- ✅ Security Guidelines
- ✅ Performance & Accessibility Standards

Would you like me to proceed with generating the complete file?
```

### Step 4: Generate Final Files
Only after user confirmation, update/create:
- `.github/copilot-instructions.md` (concise core guidance)
- `.github/project-context.md` (repo-specific context)
- `.github/docs/*.md` runbooks (workflow details)

Keep `.github/copilot-instructions.md` **under ~60 lines** and reference supporting files instead of
duplicating details. It is loaded on every single turn, so length there is paid for continuously.

#### Every claim must be traceable to a file you read

These two files are read back by later sessions as **settled fact**, without re-derivation. A wrong
line here is not a typo — it becomes precedent, gets cited, and nothing reviews it.

So for each statement you write, you must be able to name the file it came from. `package.json` for
versions, `power.config.json` for environment and data sources, the actual feature code for how
something is implemented. **If you cannot point at the file, ask instead of writing.** "None yet" and
"not configured" are good answers; a plausible guess is not.

Describing *behaviour* is where this slips, because it reads as harmless summary. Do not write that
data is filtered, cached, paginated, validated or authorised in a particular way unless you have read
the code that does it.

> Measured 2026-08-03: a filled `project-context.md` was accurate on every version, id and path —
> all verified against `package.json` and `power.config.json` — and then described the Accounts list
> as having **client-side search**. The code passed an OData `contains(...)` filter to the server, in
> a file the agent had already read. That single word contradicted the project's own data-fetching
> convention, in the file most likely to be trusted by the next session that writes a list screen.

#### Comment markers: KEEP vs DELETE AFTER FILLING IN

`.github/copilot-instructions.md` contains HTML comments with explicit markers. Honour them:

- `<!-- KEEP ... -->` — **permanent.** Leave it exactly where it is. These record *why* something in
  the file exists (for example, that the Git block is the only path those rules load from, because
  `gitflow.instructions.md` has no `applyTo`). Removing one deletes the reason and invites the next
  cleanup pass to delete the thing it was protecting.
- `<!-- DELETE AFTER FILLING IN ... -->` — setup scaffolding. Remove it once the file is filled in.

Unmarked comments: use judgement, but prefer keeping anything that explains a decision.

#### CRITICAL: preserve settled decisions, do not re-derive them

`.github/copilot-instructions.md` already exists — it was seeded from the baseline template and it
records **decisions**, not observations. Absence of evidence in the codebase is not evidence the
decision changed.

**Never delete a stated decision because the codebase doesn't demonstrate it yet.** A freshly
scaffolded project has no Tailwind, no TanStack Query, and no shadcn/ui installed. That does not mean
the project has chosen otherwise — it means nothing has been built yet.

Specifically, carry these forward verbatim unless the user explicitly says they changed:

- the **Stack** block (styling, server state, forms, testing choices)
- the **Git — always in effect** block (it is duplicated there on purpose, because
  `gitflow.instructions.md` has no `applyTo` and never auto-loads)
- the **Safety** block
- the **Where things are** pointers

What you *should* update from analysis: project name and purpose, actual versions, the package
manager **if the lockfile contradicts the stated one**, real integrations, and real scripts.

If your analysis genuinely conflicts with a stated decision (e.g. the project already uses Fluent UI
and the file says shadcn/ui), **surface the conflict and ask** — do not silently resolve it.

## Output Requirements

### Core File Structure Template

Keep the section structure the existing `.github/copilot-instructions.md` already uses — do not
reshape it into a different outline:

1. **Identity** (Copilot identification, response language)
2. **Stack** (framework, package manager, and the settled styling/state/forms/testing decisions)
3. **Working rules** (read project-context and project-memory, scope discipline, validate before done)
4. **Git — always in effect** (Gitflow, branch naming, commit format — preserved verbatim)
5. **Safety** (secrets, `VITE_` exposure, confirmation for destructive actions)
6. **Where things are** (pointers to instructions/, prompts/, agents/, docs/reference/)

Detailed per-language and per-framework guidance does **not** belong here — it lives in
`.github/instructions/*.instructions.md`, auto-applied by `applyTo` glob. Putting it in this file
loads it on every turn regardless of what is being edited.

### Content Guidelines
- **Be specific to the analyzed project** - avoid generic boilerplate
- **Reference exact versions** found in the codebase when relevant
- **Include actual file paths** and configuration patterns
- **Maintain consistency** with existing `.github/instructions/` files
- **Keep core instructions concise**; move long procedures to docs/prompts
- **Use actionable language** - "Use X for Y" not "Consider using X"

## Quality Checklist

Before finalizing, ensure the generated setup:
- [ ] Accurately reflect the analyzed technology stack
- [ ] Include version requirements when they materially affect implementation
- [ ] Reference existing instruction files appropriately
- [ ] Provide clear, actionable guidelines
- [ ] Keep `.github/copilot-instructions.md` concise (target under 150 lines)
- [ ] Match the project's actual development workflow
- [ ] Include project-specific security and performance requirements

Remember: The goal is to create instructions that will help GitHub Copilot generate code that seamlessly integrates with the existing project structure and follows established patterns.
