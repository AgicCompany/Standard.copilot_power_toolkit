---
name: pr-description
description: 'TRIGGER - read this BEFORE writing the description of a pull request, or before running gh pr create / gh pr edit with a body: when delivery opens a PR, when asked to "fill the PR", or when a PR description is still the empty template. It fills the repository''s PR template from evidence only (branch, issue, commits, diff, checks actually run) and marks everything only a person can know as TO FILL IN instead of guessing it. Do NOT skip because the template "looks simple": a description that says "verified live" or "all tests pass" without having run anything is worse than an empty field. SKIP for commit messages and for review replies.'
---

# PR description

A PR description is evidence for the reviewer. Every line in it is either something you checked in
this session, or it says plainly that a person must fill it in. Never write a result you did not
observe: no test counts you did not see, no "verified in DEV", no ticked checklist item you cannot
prove.

## 1. Find the template, do not assume one

GitHub accepts a PR template in three folders: `.github/`, the repository root, and `docs/`. In each,
look (case-insensitive) for `pull_request_template.md`, and for a `PULL_REQUEST_TEMPLATE/` folder of
named templates. Search all three before concluding there is none.
- One template found: use it.
- Several named templates: ask the person which one applies (or pick the one the issue or branch type
  clearly matches, and say which you chose).
- None: write the description from the plan in context (Overview, Steps, Testing) and say that the
  repository has no PR template.

With a template, keep its headings, order and checklist exactly: fill them in, do not redesign them.
Remove the `<!-- hint -->` comments you have replaced.

## 2. Gather the evidence before writing anything

| Section | Evidence | How |
|---|---|---|
| Issue (`Closes #n`) | the branch name, `feature/<n>-…` | `git branch --show-current`. No number in the name: ask, do not invent one |
| What | commits and the diff against the base branch | `git log --oneline <base>..HEAD`, `git diff --stat <base>...HEAD`. The base is the PR's target, normally `develop` |
| Scope (functional sections, requirements) | the issue body | `gh issue view <n> --repo <owner>/<repo>`; compare what it asks with what the diff does, and state any deviation |
| Tests, lint, build | results produced **on the exact commit being described** | first reuse evidence from this session for that commit (the `checklist` agent's gate report, `logs/copilot/build-gate/gate.log` with its commit or timestamp). Only if there is none, read the nearest `package.json` (and the test project for .NET) and run the scripts it defines, single-run form. Copy the real summary line; nothing for that commit: say "not run" |
| Changes outside the code (environments, deployments, data) | the paths the diff touches | name what the paths imply (for example an exported solution package changed, a new API definition folder), not what you suppose was done |
| Data model | generated schema files or docs in the diff | changed or not; a linked data-model issue if there is one |

Never reuse a number produced on an earlier commit: after a new commit the old result says nothing.
If a check failed, the description says so and the PR is not ready: stop and report that instead of
opening it.

## 3. What only a person can supply: mark it, never fill it

Write `TO FILL IN` (and keep the hint) for:
- anything checked in a live environment ("submitted a request in the test environment, record
  REQ-0042 was created");
- screenshots and comparisons with mockups;
- checklist items about what the person did (plan posted and reviewed, the executor did not commit).

A checklist box is ticked only when the evidence is in this session. Otherwise leave it empty and add
the reason in a few words, or leave it for the person.

## 4. Open or update the PR

- Write the body to a file and pass it with `--body-file`; long bodies break shell quoting.
- Name the repository explicitly: `gh pr create --repo <owner>/<repo> --base <base> --head <branch>
  --title "<conventional title>" --body-file <file>`, or `gh pr edit <n> --repo <owner>/<repo>
  --body-file <file>`. Never rely on the current folder to choose the repository.
- Report what happened: the PR URL, and which sections still say TO FILL IN.
