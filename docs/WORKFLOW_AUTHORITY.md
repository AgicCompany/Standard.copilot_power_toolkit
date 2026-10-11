# Workflow Authority

Purpose: Single baseline branching and release model for repositories using this governance template.

## Canonical Model
- Gitflow is the baseline model.

## Required Branches
- main
- develop
- feature/*
- release/*
- hotfix/*

## Repository Settings
- **`develop` is the repository's default branch on GitHub**, set on day one. `main` stays the
  production branch: protected, and changed only by `release/*` and `hotfix/*` merges.
- Why it matters: GitHub reads several things only from the default branch. With `main` as default,
  none of them work until the first release: PR templates and issue templates are not offered,
  `Closes #N` does not close issues on merges into `develop`, new PRs target `main`, Dependabot reads
  its configuration from `main`, and the Copilot cloud agent loads hooks only from the default branch.

## Pull Request Expectations
- No direct pushes to protected branches.
- At least one reviewer approval.
- Required checks pass before merge.
- Keep changes small and focused.
- Answer every review finding in its thread (fixed in which commit, or why it does not apply), then
  resolve it.
- Do not re-request an automated review after every fix: each new review reads the whole PR again
  and can keep producing findings indefinitely. A person checks the fixes; re-request only after a
  large change.

## Release Discipline
- Use release/* for stabilization.
- Use hotfix/* for urgent production fixes.
- Tag release commits with semantic versioning.

## Conflict Rule
- If other workflow docs exist, this file is the default authority.
- Any override must be explicitly documented in the same repository.
