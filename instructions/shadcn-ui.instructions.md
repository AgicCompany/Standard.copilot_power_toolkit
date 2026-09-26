---
description: 'Styling authority for this baseline — Tailwind v4 + shadcn/ui. Defines what is generated vs hand-written and how to compose components.'
applyTo: '**/*.{tsx,jsx}'
---

# Styling: Tailwind v4 + shadcn/ui

**This is the single styling authority.** No CSS Modules, styled-components, or Emotion. Fluent UI
is an opt-in alternative for projects matching native Power Platform chrome — only if
`fluent-ui-v9.instructions.md` is present.

Setup sequence, CLI failure modes, and the incidents behind these rules:
[`docs/reference/shadcn-setup.md`](../docs/reference/shadcn-setup.md).

## Preconditions — check before writing a single Tailwind class

**Tailwind class names are just strings.** A project without Tailwind installed compiles,
type-checks, lints, builds, and passes every test while rendering **completely unstyled** — no error
at any stage. This is the only rule here whose violation is invisible to every automated gate, which
is why `build-gate` also checks it mechanically.

1. **Tailwind installed?** `tailwindcss` + `@tailwindcss/vite` in `package.json`, plugin in
   `vite.config.ts`, `@import "tailwindcss";` in the CSS entry point. Not there → **install and wire
   it.** Reporting that styling will not render is what you do when the install *fails* — not
   instead of attempting it. Never quietly emit unusable classes.
2. **shadcn/ui initialised?** `components.json` and `lib/utils.ts` exist. Not there → follow the
   ordered sequence in `docs/reference/shadcn-setup.md`. **Path aliases must be configured in both
   tsconfigs *before* `init`**, or it fails with "Could not load the workspace config" — that error
   means missing aliases, not a broken CLI. Never switch to `@canary` to work around it.
3. **Semantic tokens require the theme.** `bg-primary`, `text-muted-foreground` and friends are CSS
   variables written by `shadcn init`. Installing `clsx` + `tailwind-merge` gives you the merge
   helper, **not** the theme.

**Check all three BEFORE writing the first class name.** If any is missing you have two acceptable
moves — **set it up, or ask which the user prefers — and either happens first, before the component
exists.** These are settled decisions (`copilot-instructions.md`), so wiring one up implements a
choice already made rather than expanding scope.

The failure mode is the third option: emitting the classes anyway and offering to set Tailwind up
afterwards. That leaves the user with a component that renders unstyled *and* a decision to make
*and* rework to do. **Asking is fine. Asking after the file is written is not.**

## Install what the convention requires — never approximate it

If a convention depends on a package that isn't installed, **install it**:

- `cva` missing → `pnpm add class-variance-authority`, not a hand-rolled variant `Record`.
- shadcn component missing → `pnpm dlx shadcn@latest add <name>`, not a styled `<div>`.
- Tailwind or theme missing → set them up.

Each substitution looks reasonable alone. Together they produce a component satisfying none of these
conventions while appearing to satisfy all of them.

**"I'll skip it and mention it" is not one of the options.** Declaring an omission is what you do
when something is genuinely blocked — not a cheaper way to satisfy the rule. **Scaling the work down
is the user's call, not yours.** A package you have not tried to install is not a block; it is a
prerequisite you skipped.

Reserve the declare-and-skip path for an actual failure — you **ran** the install command and it did
not succeed. Then, in this order:

1. Quote the exact command and its error. That is the finding, not something to route around.
2. Complete every part of the task that does not depend on it.
3. Name precisely which conventions are now unmet, and why.

### When the CLI fails, do NOT hand-write the component

"I know this component well, I'll write it from the shadcn source" is always wrong — you don't know
which style, primitive library, or registry version this project uses, and the version you remember
is probably the Radix one.

1. **Say the CLI failed and quote the error.** That is the finding, not something to work around.
2. **Build with what is installed**, wiring `htmlFor` / `aria-describedby` / `aria-invalid` by hand.
3. **Never install a second primitive library to make a hand-written file compile.** Check what
   `components/ui/` already imports first.
4. **Stop and ask** if neither works. A blocked task reported honestly beats an unblocked one that
   quietly forks the project's foundations.

## `src/components/ui/**` is generated code

- **Never hand-write a shadcn component.** Add it with the CLI.
- **Don't edit `ui/` files for app-specific behaviour** — wrap or compose instead: a `<SubmitButton>`
  in `components/` that renders `<Button>`, not a new prop on `ui/button.tsx`.
- Editing a `ui/` file is legitimate only for a deliberate project-wide restyle — it makes future
  updates a manual merge, so say so when you do it.
- **Never use `window.confirm` / `alert` / `prompt`.** "A confirmation dialog" means a
  `Dialog`/`AlertDialog` — install it if missing. Native dialogs can't be styled, ignore the theme,
  and **are suppressed inside an iframe** without `allow-modals`, where `confirm()` silently returns
  `false`. Power Apps Code Apps run in an iframe, so "confirm before destructive action" becomes
  "the action never happens", with no error.

  **This rule does not depend on shadcn already being installed.** "shadcn isn't set up, so I'll use
  `window.confirm`" — and its variants "adding dependencies is out of scope" and "I'll hand-roll a
  native `<dialog>` to avoid setup overhead" — are the exact failures it exists to prevent, all three
  observed live on 2026-08-01/02.

  **If this project is configured for shadcn, install the component.** `pnpm dlx shadcn@latest add
  alert-dialog`. Hand-rolling something shadcn provides is the same violation as
  [line 125's](#) "don't add a UI dependency for something shadcn already provides", pointing the
  other way: it produces a bespoke component that matches nothing else in the app and must be
  maintained by hand forever, to avoid one install. The same rule is in
  `power-apps-code-apps.instructions.md`, which loads regardless of UI library.

## Composing

- **Use `cn()`** (the `clsx` + `tailwind-merge` helper in `lib/utils.ts`) for every conditional or
  merged class list. Template strings produce conflicts Tailwind resolves by source order, not intent.
- **Accept `className` on every component** and merge it last via `cn()`.
- **Use variants, not booleans.** `cva` variants (`variant="destructive"`) over `isDestructive` /
  `isPrimary` pairs that can contradict each other.
- **Check which primitive library this project uses before composing.** `@radix-ui/*` composes via
  `asChild`; `@base-ui/react` composes via `render` and has **no `asChild`**. `asChild` dominates the
  examples online, so it's the default guess and it fails silently on Base UI. Copy the pattern from
  a component already in this repo, not from memory.

## Tailwind usage

- **Design tokens over arbitrary values.** `p-4`, `text-muted-foreground` — not `p-[17px]` or
  `text-[#64748b]`. Arbitrary values signal the token scale needs extending in CSS.
- **Use the semantic colour variables** (`background`, `foreground`, `muted`, `primary`,
  `destructive`, `border`). Raw palette colours (`bg-slate-800`) bypass theming and break dark mode.
- **Need a status colour the theme lacks?** shadcn has **no `success`/`warning` token**. Extend the
  theme via `@theme { --color-success: ... }` in the CSS entry point — see
  `docs/reference/shadcn-setup.md`. Don't fall back to `bg-green-100`; it ignores dark mode and
  drifts from every other status colour. Extending the theme is expected, not scope creep.
- **Dark mode must work.** Semantic tokens give this free; hardcoded colours do not.
- **Order long class lists by concern** (layout → spacing → typography → colour → state). An
  unreadable class list means the component wants splitting.
- **Mobile-first**: unprefixed base styles, then `sm:`/`md:`/`lg:`. Never a `max-*` variant where a
  mobile-first one works.

## What not to do

- No inline `style={{}}` except genuinely dynamic values (computed transform, chart dimension).
- No global CSS beyond `index.css` (Tailwind import, theme variables, base resets).
- No `!important` / `!` prefix — that's a specificity problem to fix, not a workaround.
- Don't add a UI dependency for something shadcn already provides.
