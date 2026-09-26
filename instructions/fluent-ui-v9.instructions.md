---
description: 'Opt-in alternative to shadcn/ui for projects that must visually match native Power Platform chrome. Ships only with apply-baseline.ps1 -Ui fluent, which also removes shadcn-ui and tailwind.'
applyTo: '**/*.{tsx,jsx}'
---
<!--
OPT-IN: this file is deliberately excluded from every profile in tools/baseline-profiles.json.
The baseline default is Tailwind v4 + shadcn/ui (`shadcn-ui.instructions.md`). Ship EITHER this file
OR that one into a project, never both — two styling authorities in context is exactly the ambiguity
the baseline is trying to remove. Choose Fluent when the app must sit visually inside Model-Driven /
Canvas surroundings; choose shadcn otherwise.
-->

# Styling: Fluent UI v9

**This is the single styling authority when present.** Do not mix with Tailwind utilities,
CSS Modules, or another CSS-in-JS library.

Package: `@fluentui/react-components` (v9). This is the version used by official Power Apps Code App
samples; v8 (`@fluentui/react`) is a different API — do not mix the two.

## Setup

- The app is wrapped once in `<FluentProvider theme={webLightTheme}>` (or the dark/team theme).
  Nested providers are only for a deliberately themed subtree.
- Theme selection lives in one place, not per component.

## Styling rules

- **`makeStyles` + `tokens`, always.** No inline `style={{}}` except genuinely dynamic values, and no
  raw hex colours or pixel spacing — `tokens.colorNeutralForeground1`, `tokens.spacingHorizontalM`.
  Hardcoded values break theming and high-contrast mode.
- **`mergeClasses`** to combine style hooks conditionally — not template-string concatenation.
- Define styles at module scope via `makeStyles`, never inside the component body.

## Components

- **Use the Fluent component before building one.** `Button`, `Field`, `Input`, `Dialog`,
  `DataGrid`, `Combobox`, `Toast` cover most of what a Code App needs, and they carry the
  accessibility behaviour with them.
- **`Field`** wraps label, hint, and validation for inputs — it is what wires `htmlFor`,
  `aria-describedby`, and error state. Prefer it over a hand-composed `Label` + `Input`.
- **`DataGrid`** for tabular Dataverse data; pair with virtualisation for large result sets rather
  than rendering every row.
- **`Toaster`/`useToastController`** for transient feedback, `Dialog` for anything requiring a
  decision.

## Accessibility

Fluent v9 components implement focus management and ARIA correctly — **do not add `role` or `aria-*`
attributes the component already manages**, and do not re-implement focus trapping in a `Dialog`.
What still needs verifying: an accessible name on every icon-only `Button`, correct heading structure
inside surfaces, and that custom compositions keep keyboard order sane.

The rest of `a11y.instructions.md` still applies.
