---
description: 'Error handling for React/Vite apps — boundary placement, what users see, and what gets logged.'
applyTo: '**/*.{ts,tsx}'
---

# Error Handling

Three separate questions, answered separately: **does the UI survive**, **what does the user see**,
and **what do we record**. Most broken error handling answers only the third.

## Boundaries

- **Every route gets an error boundary.** A render error in one route must not blank the whole app —
  in a Power Apps Code App the user sees an empty iframe with no way to recover.
- **Wrap independently-failing widgets** (a chart, an embedded report, a third-party control) in
  their own boundary so one failure degrades a panel, not the page.
- **Error boundaries do not catch async errors, event handlers, or errors during SSR.** Those need
  explicit handling — usually TanStack Query's `error` state or a `try/catch` in the handler.
- Pair with `react-error-boundary`'s `useErrorBoundary` rather than hand-writing a class component,
  unless the project already has one.
- **Every boundary offers a way out** — a retry that resets the boundary, or a link back to a known
  good route. A dead-end error screen is a bug.

## What the user sees

- **Explain what happened and what to do next**, in the user's language. Not "Error: 400", not a
  stack trace, not a raw Dataverse fault.
- **Distinguish the cases**, because the user's action differs: not-found, no permission, validation
  rejected, network/offline, and unexpected failure are five different screens.
- **Never fail silently.** A `catch` that logs and returns is a bug unless the failure genuinely
  doesn't matter — and if so, say why in a comment.
- **Never surface raw exception text.** It leaks schema, endpoints, and sometimes data.

## What gets logged

- Log with enough context to act on: operation, entity/record id, correlation id, user action. A
  bare `console.error(e)` is not diagnosable after the fact.
- **Never log PII, tokens, connection strings, or full record payloads.** Dataverse rows routinely
  contain personal data.
- Application Insights in Code Apps works through **SDK logger configuration only** — there is no
  native integration. See `docs/reference/power-apps-code-apps-reference.md`.

## Async and data errors

- **TanStack Query owns fetch errors** — render from `isError`/`error` rather than try/catching in a
  component.
- **Configure retry deliberately**: retry transient network/5xx failures, never a 400/403/404. The
  default blanket retry turns a permission error into four permission errors and a long spinner.
- **Every mutation has an `onError`** that tells the user the write failed. A silent failed save is
  the worst outcome in a data-entry app.
- **Distinguish empty from failed.** "No records match" and "we couldn't load records" are different
  states; rendering an empty list for both hides outages.

## Types

- **Catch as `unknown`** and narrow — `catch (e: any)` defeats the point.
- Use a typed error/result at boundaries where failure is expected and routine, rather than throwing
  for control flow.
