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

## Pull Request Expectations
- No direct pushes to protected branches.
- At least one reviewer approval.
- Required checks pass before merge.
- Keep changes small and focused.

## Release Discipline
- Use release/* for stabilization.
- Use hotfix/* for urgent production fixes.
- Tag release commits with semantic versioning.

## Conflict Rule
- If other workflow docs exist, this file is the default authority.
- Any override must be explicitly documented in the same repository.
