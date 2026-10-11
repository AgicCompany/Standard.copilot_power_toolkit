---
name: baseline-review-checks
description: 'TRIGGER - read this when reviewing a pull request, a branch or a diff: Copilot code review on a PR, the review agent, or any "review this" request. It holds the review checks that come with this baseline (evidence before findings, scope against the issue, the React and Power Apps Code App traps that compile and pass tests while wrong) and points to the project''s own review skill. SKIP when writing or changing code: the auto-applied instructions cover that.'
---

# Baseline review checks

The checks every project on this baseline shares. **First read the project's own review skill,
`.github/skills/code-review/SKILL.md`, if it exists:** it lists the project's checks and its settled
decisions, and where it disagrees with this file, it wins. The baseline never ships a `code-review`
skill, so that file always belongs to the project.

## Evidence before findings

- Every finding gives `file:line`, a severity, what is wrong, and **the source you checked**: the
  instruction file, the config, the issue, the doc. A finding without a checked source is a guess:
  verify it or drop it.
- **To see what changed, use the source-control changes tool** (`search/changes`), then read the
  changed files in full. Do not review from search snippets alone, and do not ask for a terminal to
  run `git diff`.
- **"Missing behaviour" is checked against defaults first.** Before reporting that something is not
  done, search the configuration for an option that turns it off; idiomatic code relies on library
  defaults (react-hook-form focuses the first invalid field by default, for example).
- **Permission and security findings are checked against the security model** the project records
  (its data-model documentation, its project memory). Hiding a screen is user experience, not access
  control: the finding is real only if the data itself is readable or writable by the wrong role.
- **A test added for a fix must fail without the fix.** Read the test and the fix and confirm the
  assertion exercises the changed behaviour; a statement in the PR that this was verified is context,
  not proof.

## Scope against the issue

Read the issue the PR closes and compare its scope with the diff. A deviation is settled only by a
**decision**: recorded on the issue by whoever owns the scope, or listed in the project's review skill
as a settled decision. Then it is not a finding. A deviation the author merely mentions in the PR is
still reported, as a question for the scope owner ("not decided yet"), not as approved. A deviation
mentioned nowhere is a finding.

## React and TypeScript

Check against the instruction file whose `applyTo` matches the changed file, and cite it.
- Styling through the project's single styling system, and class lists merged with the helper its
  UI instruction names, never template strings: `cn()` with shadcn/Tailwind
  (`shadcn-ui.instructions.md`), `mergeClasses` with Fluent UI (`fluent-ui-v9.instructions.md`).
  Check which UI instruction the project has before judging.
- Server state through the project's query library with a key factory, not `useEffect` + `fetch`.
- Every user-visible text in every language catalogue the project keeps; no text hard-coded in JSX.
- Composition follows the primitive library the project's components are built on: read an existing
  `components/ui` file first. Base UI composes with `render` (and a `Button` that renders a link needs
  `nativeButton={false}`); Radix composes with `asChild`. Mixing the two is the finding, not either one.
- One `h1` per page; focus moves to the new view's heading after navigation.
- Tests use the real field names and values of the data they model, not values shaped to match the
  code.

## Power Apps Code Apps (when the app has a `power.config.json`)

- Generated services (`src/generated`) are imported only from a feature's `api/` folder, `src/lib`, or
  a test file (tests import them to mock them).
- Queries select explicit columns, never `$expand` (code apps cannot), and page with `skipToken`.
- A user action that writes **more than one row** goes through a Custom API: generated-service calls
  from the browser have no transaction (`power-apps-code-apps.instructions.md`,
  `skills/custom-api-authoring`). A single-row write is a judgement call: report it only when a rule
  the project states must hold on the server (a status workflow, a contended row) is enforced only in
  the browser. The project's own review skill may make this stricter.
- Dataverse ids are validated with `z.guid()`, never `z.uuid()`.
- Date-only columns are shown in UTC; date-and-time (user local) columns in the user's time zone. Check
  the column's behaviour before judging a date formatter.
- `error.message` is never rendered; plug-in errors reach the user as a code mapped to a message.
- A plug-in package built from a branch that is behind the target branch removes merged work from
  the shared environment. When the PR pushed a package, check the branch contains the target's latest
  commit (it is not "behind" on GitHub, or `git merge-base --is-ancestor <target> HEAD`). A plug-in
  test count well below the target's is a reason to check this, not proof either way.

## How to report

Rank findings by severity, real behavioural defects first. A settled decision recorded in the project's
review skill is not a finding unless the PR changes it.
