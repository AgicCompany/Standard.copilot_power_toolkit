# Release Checklist

## Pre-Release
1. Ensure target branches and PR flow follow Gitflow.
2. Confirm no direct commits on `main` or `develop`.
3. Validate conventional commit quality.

## Quality Gates
1. `<pm> run build` passes (`<pm>`: the project's package manager, from its lockfile).
2. `<pm> run lint` passes (or approved exceptions documented).
3. The critical user flows named in the project's own acceptance criteria are smoke-tested end to end.

## Security And Configuration
1. No secrets in code or configuration.
2. Dependency changes reviewed for necessity and risk.
3. Error handling remains user-safe (no sensitive detail leakage).

## Deployment Readiness
1. Release notes state the product scope delivered — features and fixes, in the terms of the
   project's own requirements. (A Canvas migration also lists the parity slices completed.)
2. Known limitations and follow-up items documented.
3. Rollback strategy or mitigation path documented if applicable.
