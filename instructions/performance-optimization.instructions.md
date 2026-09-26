---
description: 'Performance rules applied while writing React/Vite code — Core Web Vitals essentials. Full anti-pattern catalogue lives in docs/reference/performance-anti-patterns.md.'
applyTo: '**/*.{tsx,jsx}'
---

# Performance (Core Web Vitals)

Budgets: **LCP < 2.5s**, **INP < 200ms**, **CLS < 0.1**.

The complete catalogue — 50+ anti-patterns with IDs, detection regexes, framework-specific sections
(Next.js, Angular, Vue), and resource-hint/image/font quick references — is in
[`docs/reference/performance-anti-patterns.md`](../docs/reference/performance-anti-patterns.md).
Read it when profiling or chasing a specific regression. The rules below apply as you write code.

## Rendering and re-renders

- **Do not create unstable references in render.** Inline object/array/function props force children
  to re-render every time. Hoist, or memoise with `useMemo`/`useCallback` — but only where a real
  re-render problem exists, not reflexively.
- **Every list item needs a stable `key`** derived from data identity. Never the array index for
  lists that reorder, filter, or insert.
- **Virtualise long lists.** Beyond ~100 rows, render a window (`@tanstack/react-virtual`), not the
  whole set. Large result sets (paged API responses, Dataverse tables) routinely exceed this.
  **Virtualising breaks the accessible item count** — only the mounted window is in the DOM, so a
  screen reader announces "12 items" for a list of 5000. Set `aria-setsize` to the full collection
  length and `aria-posinset` to the row's real index on every item. Nothing else detects this: the
  list renders correctly, type-checks and passes its tests while reporting the wrong size to
  assistive tech. See `docs/reference/a11y-anti-patterns.md` RX5.
- **Split routes with `React.lazy` + `Suspense`.** A single monolithic bundle is the most common
  cause of a slow first paint in a Vite SPA.

## Main thread and INP

- **No long synchronous work in event handlers.** Break up, defer with `useTransition`, or move
  heavy computation off the main thread. INP is measured on the interaction users actually feel.
- **Always clean up effects** — `setInterval`/`setTimeout`, `addEventListener`, subscriptions, and
  in-flight requests. A missing cleanup is both a leak and a source of state-update-after-unmount.
- **Avoid layout thrashing**: batch DOM reads before writes; never read `offsetWidth` in a loop that
  also writes styles.

## Loading and layout stability

- **Images and media always carry explicit `width`/`height`** (or an aspect-ratio box). Missing
  dimensions are the dominant cause of CLS.
- **Never lazy-load an above-the-fold image.** Lazy-load below the fold, and mark the LCP element
  `fetchpriority="high"`.
- **Fonts**: `font-display: swap`, preload the one critical font, subset it. Unstyled/invisible text
  flashes are a CLS and LCP problem at once.
- **Reserve space for async content** — skeletons with the same dimensions as the loaded state, not
  a collapsing spinner.

## Bundle

- **Import from the specific module, not a barrel file.** `import { x } from 'lib/x'` — barrel
  imports defeat tree shaking and quietly pull in whole libraries.
- **Question every large dependency** used for a small utility. Check the cost before adding it.
- Run a bundle analysis before shipping a significant feature.

## Data fetching (Power Apps / Dataverse)

- **Never fetch in a `useEffect` you wrote by hand** when a query library is available — see
  `data-fetching.instructions.md`. Manual effects miss caching, deduplication, and cancellation.
- **Select only the columns you need** and page server-side. Over-fetching a wide Dataverse table is
  usually the real cause of a "slow React app".
- **Parallelise independent requests**; never await them in sequence.
