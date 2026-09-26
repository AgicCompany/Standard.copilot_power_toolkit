# Datasource Onboarding Runbook

## Objective
Add missing Dataverse entities/flows safely and predictably for parity work.

## Onboarding Steps
1. Identify missing datasource/flow names from Canvas references.
2. Add configuration in `power.config.json`.
3. Regenerate typed clients if required by project tooling.
4. Verify generated models/services exist under `src/generated/`.
5. Expose app-facing wrappers in `src/services/dataverse.ts`.

## Validation Checklist
- Naming is aligned with existing generated service conventions.
- Service methods return stable app-level contracts.
- KO/error branches are explicitly handled.
- Build passes after integration.

## Implementation Rules
- Keep generated code untouched when possible.
- Put app logic in wrapper/service layer, not in generated files.
- Convert flow/service errors into actionable messages for page layer.
