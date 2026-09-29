---
description: 'Unit and component testing standards for Vite + React using Vitest and React Testing Library'
applyTo: '**/*.test.ts, **/*.test.tsx, **/vitest.config.*, **/vitest.setup.*'
---

# Vitest + React Testing Library

Unit and component test conventions for this Vite + React stack. For browser-driven end-to-end
tests, see `playwright-typescript.instructions.md` instead — that's `.spec.ts` under `tests/`/`e2e/`;
this file is `.test.ts`/`.test.tsx` colocated with the source it tests.

## Never change production code to make a test pass

**The most serious anti-pattern here, because it reports success.** If a test fails, fix the test or
fix a real bug — never add a branch to the component whose purpose is to satisfy the test runner.

- ❌ A fallback path "for environments where X isn't supported", where the only such environment is
  jsdom.
- ❌ `if (import.meta.env.MODE === 'test')` / `process.env.NODE_ENV === 'test'` in a component.
- ❌ Disabling a feature when a measurement returns 0, because jsdom has no layout engine.

Two things go wrong at once: the feature you were asked for is now **untested** (the suite exercises
the fallback), and production gains a degraded path that fires whenever the condition happens to be
true for real — a container measures 0 on first paint, inside `display:none`, or in a collapsed
panel, not only in jsdom.

**jsdom has no layout.** `getBoundingClientRect()`, `offsetHeight`, and `IntersectionObserver` all
return 0/undefined. That is a fact about the test environment, so fix it in the test environment:

```ts
// Give the virtualiser something to measure - in the TEST, not the component.
beforeEach(() => {
  vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
    height: 400, width: 800, top: 0, left: 0, bottom: 400, right: 800, x: 0, y: 0,
    toJSON: () => {},
  })
})
```

Or test the layers separately: assert data/filtering/empty-state logic without the virtualiser, and
leave scroll-window behaviour to an e2e test in a real browser.

**If you cannot make it work honestly, say so** — "the virtualised path isn't covered by these tests
because jsdom has no layout; it needs an e2e test" is a genuine result. Green tests over a weakened
feature are worse than a stated gap.

## File Conventions
- Colocate: `account-card.tsx` → `account-card.test.tsx` in the same folder.
- One test file per component/module/hook under test.
- Config: `vitest.config.ts` (or the `test` block in `vite.config.ts`) with `environment: 'jsdom'`
  and a `vitest.setup.ts` that imports `@testing-library/jest-dom/vitest` — **not** the bare
  `@testing-library/jest-dom`. The bare import augments Jest's global `expect` types; only the
  `/vitest` subpath augments Vitest's own `expect`, which is what makes `tsc` actually recognize
  matchers like `toBeInTheDocument()`. Getting this wrong is what `@ts-nocheck`-on-the-test-file
  papers over instead of fixing — confirmed empirically, not just from docs.
- **Put `vitest.setup.ts` inside `src/`** (e.g. `src/vitest.setup.ts`), not at the project root, and
  point `vitest.config.ts`'s `setupFiles` at that path. The standard Vite scaffold's
  `tsconfig.app.json` has `"include": ["src"]` — a root-level setup file sits outside that scope, so
  `tsc`/`tsc -b` never loads it and its type augmentation never applies to your test files, even
  though the import is written correctly. Vitest itself doesn't care (it loads `setupFiles` directly,
  ignoring tsconfig `include`), so **tests will pass at runtime while `tsc` still reports every jest-dom
  matcher as nonexistent** — a real, confirmed split between "the tests run green" and "the types are
  actually correct." Don't debug this as a jest-dom problem; check the setup file's location first.

## Core Principles
- Test behavior, not implementation. Query the DOM the way a user would.
- Prefer React Testing Library queries in this priority order: `getByRole` > `getByLabelText` >
  `getByText` > `getByTestId` (last resort — add a `data-testid` only when no accessible query works).
- Never query by CSS class or DOM structure — it breaks on refactors that don't change behavior.
- Use `userEvent` (not `fireEvent`) for interactions — it simulates real event sequences (focus,
  keydown, click) instead of dispatching a single synthetic event.
- Use `screen.findBy*` (async) for anything that appears after a state update or async call; use
  `waitFor` only when there's no query that already waits for you.

## Structure
```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ProjectCard } from './project-card';

describe('ProjectCard', () => {
  it('shows the project name and opens detail view on click', async () => {
    const user = userEvent.setup();
    render(<ProjectCard project={{ id: '1', name: 'Request Migration' }} />);

    expect(screen.getByRole('heading', { name: 'Request Migration' })).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /view details/i }));

    expect(screen.getByRole('dialog')).toBeInTheDocument();
  });
});
```

## Mocking
- **Dataverse / Power Platform / external API calls**: mock at the service boundary (the generated
  `@microsoft/power-apps` service module or your API client), not `fetch`/`axios` internals — assert
  the component reacts correctly to the data it's given, not how the call was made.
- Use `vi.fn()` / `vi.mock()`; reset mocks in `afterEach(() => vi.clearAllMocks())`.
- For anything more than a couple of call-response pairs, prefer MSW (Mock Service Worker) so the
  mock lives at the network boundary and is reusable across tests.
- Don't mock what you're testing. If a hook wraps the Dataverse service, test the hook against a
  mocked service — don't mock the hook itself.

## Hooks
- Test custom hooks via the component(s) that use them, not `renderHook` in isolation, unless the
  hook has no meaningful UI consumer yet.

## Spend your effort on integration, not units

**Most of your testing should be integration testing** — a component rendered with its real hooks,
its real query client, and the network mocked at the HTTP boundary. Unit tests are fast to write and
cheap to run, and they are the weakest evidence that anything works.

The reason is specific, not philosophical: **a suite that mocks the service layer proves the
component talks to the mock.** It stays green while the query is unbounded, while the filter is
applied client-side, while the field name is wrong, and while the whole data layer is misconfigured —
because none of those things is what the mock does.

So:

- **Mock at the network boundary (MSW), not at the module boundary.** `vi.mock('./accountsService')`
  deletes the code under test. An MSW handler exercises the real service, the real query hook, the
  real cache and the real error path, and only substitutes the HTTP response.
- **Reserve unit tests for logic with real branching** — a filter builder, a date formatter, a
  permission check. Things where the input space is the interesting part.
- **Do not chase coverage.** A component whose lines are all executed by a test that mocks away its
  behaviour is 100% covered and 0% verified.
- **Anything that must work in a real browser is not a Vitest test.** JSDOM cannot reproduce iframe
  sandboxing, real focus order, or actual dialog semantics — those belong in Playwright.

## What to Test
- User-visible behavior: what renders, what happens on interaction, loading/error/empty states.
- Edge cases: empty lists, failed requests, permission-denied responses, boundary values.
- Skip: implementation details (internal state shape, private function calls), trivial prop
  pass-through with no logic, third-party library internals.

## Anti-Patterns
- ❌ `container.querySelector('.some-class')` — use a role/label/text query instead.
- ❌ Snapshot-testing entire components — snapshots rot silently and get rubber-stamped on update.
- ❌ `await new Promise(r => setTimeout(r, 100))` — use `findBy*`/`waitFor` instead of a fixed delay.
- ❌ Testing library internals of a third-party component — test your usage of it, not its guts.
- ❌ One giant test asserting the whole component — split into focused `it()` blocks per behavior.

## Running
- `pnpm test` — watch mode during development
- `pnpm test -- --run` — single run (CI)
- `pnpm test -- --coverage` — coverage report
