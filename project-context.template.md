# Project Context

Fill this file after copying the template into a target project. Delete the italic hint text as
you go — this file should read as facts about the project, not a blank form.

## Project Identity
- Project name: *e.g. "Field Service Dispatch App"*
- Domain: *e.g. "Power Apps Code App for dispatch scheduling, replacing a Canvas app"*
- Business goal: *One sentence — what breaks or what improves if this ships*

## Technical Stack
- Frontend: *e.g. React 19 + TypeScript + Vite*
- Backend: *e.g. none — Dataverse via `@microsoft/power-apps` generated services*
- Data platform: *e.g. Dataverse (table names, key entities if known)*
- Package manager: *the one the lockfile shows — `package-lock.json` npm, `pnpm-lock.yaml` pnpm,
  `yarn.lock` yarn. No lockfile yet: choose one and write it here. Copilot never suggests another.*

## Critical Integrations
- External APIs: *Name each one and what it's used for*
- Identity/Auth: *e.g. Entra ID via Power Platform connection, SSO scope*
- CI/CD platform: *e.g. Azure DevOps pipeline name, or "none yet"*
- Monitoring: *e.g. Application Insights resource name, or "none yet"*

## Environment Notes
- Development: *Local dev URL/command, any required local services*
- Test/Staging: *Environment name/URL, how it's populated*
- Production: *Environment name/URL, deploy approval process*

## Constraints
- Compliance/security constraints: *e.g. data residency, PII handling rules, or "none known"*
- Performance constraints: *e.g. target load time, record volume Dataverse queries must handle*
- Accessibility constraints: *e.g. WCAG 2.2 AA required — ties to `instructions/a11y.instructions.md`*

## Source Of Truth
- Primary docs: *Link to the PRD/spec/wiki that wins in a disagreement*
- Legacy parity references: *If migrating, path to the old app's source (e.g. Canvas `.fx.yaml`/`.pa.yaml`)*
- Data schema references: *Where the Dataverse solution/schema is defined or exported*
