# Release Checklist

## Pre-Release
1. Ensure target branches and PR flow follow Gitflow.
2. Confirm no direct commits on `main` or `develop`.
3. Validate conventional commit quality.

## Quality Gates
1. `pnpm run build` passes.
2. `pnpm run lint` passes (or approved exceptions documented).
3. Critical user flows smoke-tested (Request list/edit/save, project edit/setup).

## Security And Configuration
1. No secrets in code or configuration.
2. Dependency changes reviewed for necessity and risk.
3. Error handling remains user-safe (no sensitive detail leakage).

## Deployment Readiness
1. Release notes include major parity slices completed.
2. Known limitations and follow-up items documented.
3. Rollback strategy or mitigation path documented if applicable.
