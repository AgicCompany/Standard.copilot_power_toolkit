# shadcn/ui + Tailwind v4 — Setup Reference

Long-form material backing `instructions/shadcn-ui.instructions.md`. That instruction file carries
the rules Copilot applies while writing components; this document holds the setup sequence and the
incident history behind each rule.

Read this when initialising shadcn/ui in a project, when the CLI errors, or when you want to know
why a rule in the instruction file is worded the way it is.

---

## Initialisation order (the order is the whole point)

1. `pnpm add tailwindcss @tailwindcss/vite` and wire the plugin into `vite.config.ts`
2. Add `"paths": { "@/*": ["./src/*"] }` to **both `tsconfig.json` and `tsconfig.app.json`** — Vite
   splits TS config across files and shadcn reads both.
   **Do not add `"baseUrl"`.** Most shadcn guides still show it, but TypeScript 6 reports it as
   **error TS5101** (deprecated, removed in 7), which fails `tsc -b` and therefore fails
   `build-gate` — a permanent red typecheck on a project that is otherwise fine. A `paths` entry
   written as `./src/*` resolves relative to the tsconfig without it. Verified on TS 6.0.3.
3. Add the matching `resolve.alias` for `@` in `vite.config.ts` (needs `@types/node`)
4. **Only now** `pnpm dlx shadcn@latest init`, then `pnpm dlx shadcn@latest add <component>`
5. Add `src/components/ui/**` to the ESLint ignores — in the Vite flat config that is
   `globalIgnores(['dist', 'src/components/ui/**'])` in `eslint.config.js`.
   The CLI's own output trips `react-refresh/only-export-components`, because `button.tsx` exports
   both the component and `buttonVariants`. Without this, `pnpm lint` fails immediately after the
   first `add` and `build-gate` reports a `lint` failure forever, on code you did not write and must
   not edit (see `shadcn-ui.instructions.md` — `src/components/ui/**` is generated).

### "Could not load the workspace config"

This error means **the path aliases are missing**, not that the CLI is broken. Do steps 2-3 and
re-run.

**Do not switch to `shadcn@canary` or an older pinned version to work around it.** `shadcn@latest`
supports Tailwind v4 — the official Vite guide uses `@latest` throughout.

> **Incident, 2026-07:** an agent ran `init` before configuring aliases, hit this error, concluded
> shadcn was incompatible with Tailwind v4, and escalated through three CLI versions to `@canary`.
> That landed the project on pre-release output using the `base-nova` style and **Base UI**
> (`@base-ui/react`) instead of Radix. Two tests later, a CLI registry miss on the `form` component
> caused the agent to hand-write `form.tsx` from the Radix-based shadcn source it remembered, then
> install `@radix-ui/react-slot` and `@radix-ui/react-label` to satisfy its own imports — leaving
> two primitive libraries in one codebase. One skipped prerequisite, four compounding steps.

---

## When the CLI fails

Never hand-write the component. The version you remember is probably the Radix one, and you do not
know which style or registry version this project uses.

1. Say the CLI failed and quote the error — that is the finding.
2. Build with what is already installed, wiring `htmlFor` / `aria-describedby` / `aria-invalid` by
   hand if needed.
3. Never install a second primitive library to make a hand-written file compile.
4. Stop and ask if neither option is acceptable.

---

## Primitive libraries: Radix vs Base UI

shadcn components are built on a headless primitive library, and **which one depends on the style**:

| | Radix (`@radix-ui/*`) | Base UI (`@base-ui/react`) |
|---|---|---|
| Composition | `asChild` prop | `render` prop — **no `asChild`** |
| Seen in | most online examples, older styles | newer styles (e.g. `base-nova`) |

`asChild` is the default guess because it dominates the examples online, and it fails silently on
Base UI. Open a file in `components/ui/` and check the import before composing.

---

## Why the Tailwind precondition is checked mechanically

Tailwind class names are just strings. A project without Tailwind installed **compiles,
type-checks, lints, builds, and passes every test while rendering completely unstyled** — no error
at any stage.

> **Incident, 2026-07:** the "check Tailwind is installed first" instruction failed to bind in six
> separate contexts — direct prompt, planning, TDD execution, refactor, `checklist` review, and
> `review` code review. It is now enforced by the `build-gate` hook's `tailwind_not_installed`
> check rather than by prose. See `hooks/build-gate.README.md`.

---

## Native browser dialogs

`window.confirm` / `alert` / `prompt` are **suppressed inside an iframe** whose sandbox lacks
`allow-modals` — `confirm()` silently returns `false`. Power Apps Code Apps run in an iframe, so
"confirm before destructive action" degrades into "the action never happens", with no error.

> **Incident, 2026-07:** asked for "a confirmation dialog", an agent used `window.confirm` because
> the instruction only forbade hand-written components, not native APIs. Adding one explicit line
> flipped the same prompt to `shadcn add dialog` on re-run — the cleanest single-variable result in
> the whole test series.

---

## Extending the theme with status colours

shadcn ships `destructive` but has **no `success` or `warning` token**. Add them once in the CSS
entry point rather than falling back to palette classes:

```css
@theme {
  --color-success: oklch(0.72 0.15 155);
  --color-success-foreground: oklch(0.98 0 0);
  --color-warning: oklch(0.80 0.15 85);
  --color-warning-foreground: oklch(0.25 0 0);
}
```

This makes `bg-success` behave exactly like `bg-destructive`, including in dark mode.
