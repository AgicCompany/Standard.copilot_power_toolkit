---
description: 'React + TypeScript conventions for this baseline — the decisions Copilot should not re-litigate per file.'
applyTo: '**/*.{ts,tsx}'
---

# React + TypeScript

Reply in the language the user writes in (EN/IT). Keep technical terms, code, and paths unchanged.

This file records **decisions**, not general advice. Generic React best practice is assumed; what
follows is what this baseline has actually chosen, so Copilot stops re-deciding it per file.

## The decisions

| Concern | Decision |
|---|---|
| Styling | Tailwind v4 + shadcn/ui — see `shadcn-ui.instructions.md` |
| Server state | TanStack Query — see `data-fetching.instructions.md` |
| Forms | react-hook-form + Zod — see `forms-and-validation.instructions.md` |
| Client state | `useState` locally; Context only for genuinely app-wide concerns |
| **URL state** | Search, filters, pagination, selected tab — in the URL, never `useState` |
| Errors | Error boundaries at route level — see `error-handling.instructions.md` |
| Tests | Vitest + RTL (`vitest-react-testing.instructions.md`), Playwright for e2e |

**Redux, Zustand, MobX, styled-components, Emotion, axios, moment, lodash** — each has a chosen
alternative above, or is unnecessary in a modern React/Vite app.

- **Never add one on your own initiative.**
- **If the user asks for one, say so before installing.** One sentence naming the conflict and the
  chosen alternative — *"this project settled on TanStack Query for server state and `useState`/
  Context for client state; Redux would be a third state system. Want me to proceed anyway?"* — then
  **do exactly what they say.** The user overriding a decision is legitimate; the failure is
  installing it without them knowing a decision existed.
- This is not a veto. Raise it once, accept the answer, move on.

## URL state — the category everyone forgets

**If a user would reasonably expect to share, bookmark, or return to a view, its state belongs in the
URL** — search terms, filters, pagination, sort order, the selected tab.

```tsx
const [search, setSearch] = useState('');        // ❌ unshareable; back button does nothing
const [params, setParams] = useSearchParams();   // ✅ shareable, survives refresh, back works
```

- **The URL is the single source of truth — never mirror it into `useState`.** Two copies disagree
  the moment someone edits the address bar or presses back.
- **Reset the page to 0 in the same update as any filter change**, or you land on page 5 of a 2-page
  result and see an empty list.
- URLs are user-editable input: `?page=banana` will reach your code.

Debouncing, `replace` vs `push`, and parsing with Zod: `docs/reference/url-state.md`.

## Definition of done for a new component

Non-negotiable, and **not conditional on the request mentioning them**. A request for "a component"
is a request for all of this. Delivering only the bare component is an incomplete task, not a
minimal one.

**Check every prerequisite below BEFORE writing the first line of the component.** That is the whole
rule, and it is about *order*, not permission. Look for the packages, the aliases, the `cn()` helper,
the test runner. If something is missing you have two acceptable moves — **install it, or ask which
the user wants — and either one happens first, before any component code exists.**

The failure this prevents is the third option: building the degraded version, then offering to set
things up afterwards. That is not a smaller task, it is a different one — the user now has code that
does not run, plus a decision to make, plus the work of going back. Confirmed live twice: a component
written against `@/lib/utils` and `@testing-library/react` in a project that had neither, delivered as
complete; and the same component built without `cn()` or a test, with setup offered as a follow-up.
**Asking is fine. Asking after you have already written the file is not.**

Once the prerequisites are in place, the items below are not optional and not conditional on the
request naming them. A silent omission is the worst outcome — it looks identical to a finished task.
Declaring an omission is what you do when something is genuinely **blocked**, not a cheaper way to
satisfy the rule: **scaling the task down is the user's call, not yours.**

A real blocker is something you **attempted** and could not complete. It sounds like: *"no colocated
test — `pnpm add -D vitest @testing-library/react` failed, output below."* When that happens: quote
the command and error, finish every item that doesn't depend on it, and name exactly which of these
are unmet. "The project has no test runner so I didn't add one unasked" is not a blocker — it
describes a prerequisite you never checked.

1. **Typed props**, named export, `PascalCase.tsx` matching the component name.
2. **Accepts `className`**, merged last via `cn()` — even when the first caller doesn't pass one.
3. **A colocated `<Name>.test.tsx`** querying by role/accessible name with `userEvent`.
4. **Styling that actually resolves.** If Tailwind or the shadcn theme isn't set up yet, set it up
   or say plainly that it isn't — see `shadcn-ui.instructions.md` preconditions. Never emit classes
   that silently resolve to nothing.
5. **Keyboard-operable and accessibly named** if it's interactive.
6. **No branch in the component exists to make a test pass.** No `NODE_ENV === 'test'`, no "fallback
   for environments where X isn't supported" when the only such environment is jsdom, no disabling a
   feature because a measurement returned 0. jsdom has no layout engine — fix that in the test (mock
   the measurement), not in the component. Otherwise the feature ships untested *and* production
   gains a degraded path that fires on first paint, in a hidden tab, or under `display:none`.
   Full guidance: `vitest-react-testing.instructions.md`.

`skills/component-scaffold` has the full walkthrough and templates. That skill is loaded at the
model's discretion, so the five points above are repeated here — in a file that auto-applies to
every `.tsx` — precisely so they don't depend on the skill being noticed.

## Types

- **No `any`.** Use `unknown` at boundaries and narrow. If a type is genuinely unknowable, write the
  reason in a comment.
- **`type` for unions and component props; `interface` for object contracts** meant to be extended.
  Be consistent within a file rather than mixing.
- **Derive, don't duplicate**: `type Status = (typeof STATUSES)[number]`, `Pick`/`Omit` over
  re-declaring a shape that already exists.
- **Never assert your way out of a type error** (`as SomeType`) — fix the type. `as const` and
  `as unknown as X` at a genuine boundary are the exceptions.
- Prefer `readonly` arrays/props where mutation isn't intended.

## Components

- **Function components only.** Named exports, one component per file, `PascalCase.tsx` matching the
  component name.
- **Props are typed inline or as `Props`** — no `React.FC` (it adds implicit children and buys
  nothing).
- **A component that fetches, transforms, and renders is doing too much.** Fetching belongs in a
  hook, transformation in a pure function, rendering in the component.
- **Custom hooks are the unit of reuse**, not higher-order components or render props.
- Keep the file under ~200 lines. Past that, split — usually a sub-component or a hook wants to exist.

## Hooks

- **`useEffect` is for synchronising with something outside React** — a subscription, a DOM API, a
  timer. It is *not* for fetching (use TanStack Query) and *not* for deriving state from props
  (compute during render).
- **Always clean up** subscriptions, timers, and listeners in the returned function.
- **Never disable `react-hooks/exhaustive-deps`.** A dependency you want to omit means the effect is
  structured wrong.
- **Memoise only in response to a measured problem.** `useMemo`/`useCallback`/`React.memo` on
  everything adds noise and its own cost.

## Project structure

```
src/
├── components/ui/     # shadcn/ui — generated, see shadcn-ui.instructions.md
├── components/        # shared app components
├── features/<name>/   # feature-scoped components, hooks, and types
├── hooks/             # shared hooks
├── lib/               # pure utilities, no React
├── generated/         # Power Apps CLI output — never hand-edited
└── routes/            # route components
```

- **Import from the specific module, not a barrel file.** Barrel files defeat tree shaking and cause
  circular imports.
- Use the `@/` alias for cross-feature imports; relative paths only within the same feature.
- **A feature never imports from another feature's internals** — promote the shared piece to
  `components/`, `hooks/`, or `lib/` instead.

### These three rules are enforced, not just written

`.github/eslint/import-boundaries.mjs` turns them into lint errors — plus kebab-case file and folder
names — and generates its cross-feature zones by reading `src/features/`, so a new feature is covered
the moment it exists.

```bash
pnpm add -D eslint-plugin-import-x eslint-plugin-check-file
```
```js
import boundaries from './.github/eslint/import-boundaries.mjs';
export default [ ...yourExistingConfig, ...boundaries ];
```

**Do not edit that file inside a project** — it is baseline-owned and replaced on every re-sync. Its
header explains every zone; if one is wrong for your layout, say so and it gets fixed for everyone.
