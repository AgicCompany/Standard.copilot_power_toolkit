# Safety Guardrails

Purpose: Define baseline safety controls for AI-assisted development across all projects.

## Risk Levels
- Low: Read-only actions, docs updates, non-critical refactors.
- Medium: Code edits affecting runtime behavior, dependency changes.
- High: Destructive operations, production-impacting actions, credential or policy changes.

## Blocked Actions
- Execute destructive filesystem commands without explicit user confirmation.
- Run force push or history-rewrite commands on shared branches without explicit user confirmation.
- Expose, print, or commit secrets (tokens, keys, passwords, connection strings).
- Deploy to production directly from unreviewed or unapproved changes.

## Confirmation Required
- Deletion of multiple files.
- Branch deletion, force push, reset-like history changes.
- Production configuration changes.
- Infra and pipeline modifications that impact release controls.

## Secret Handling
- Never hardcode secrets in source or docs.
- Use secure secret stores and environment-based injection.
- Redact sensitive values in logs and diagnostics.

## Pre-Release Safety Checks
- Lint and build pass.
- Security-sensitive diffs reviewed.
- Branch and approval policy satisfied.
- Rollback notes prepared for production-impacting changes.

## Enforcement Model
- Sprint 1: Advisory warnings for medium/high risk.
- After tuning: Blocking for high-risk categories.

## Scope
- This file is baseline policy for repository Copilot governance.
- Project-specific exceptions must be documented in the same repository with clear rationale.
