---
description: 'Rules for reading and writing Power Apps Canvas YAML (.pa.yaml / .fx.yaml). Full schema reference lives in docs/reference/power-apps-canvas-yaml.md.'
applyTo: '**/*.pa.yaml, **/*.fx.yaml'
---

# Power Apps Canvas YAML

Canvas source unpacked by `pac canvas unpack`. The complete v3.0 schema — root structure, control
types, component definitions, data sources, editor state, and the full Power Fx formula reference —
is in [`docs/reference/power-apps-canvas-yaml.md`](../docs/reference/power-apps-canvas-yaml.md).
Read it when you need the exact shape of a section; do not guess at schema.

## This is generated source, not hand-authored code

`.pa.yaml` and `.fx.yaml` are produced by `pac canvas unpack` and consumed by `pac canvas pack`.

- **Prefer editing in the Canvas designer and re-unpacking.** Hand-edits that do not round-trip
  through `pack` produce an app that fails to open, and the error rarely names the offending line.
- Editor state under `EditorState` is tooling metadata. Do not hand-edit it, and do not treat a diff
  in it as meaningful.
- If you must edit YAML directly, keep the change minimal and re-pack to verify before moving on.

## Power Fx is declarative, not procedural

Power Fx follows Excel semantics: formulas re-evaluate automatically when anything they reference
changes. Reading it as imperative code is the most common way to misread a Canvas app.

- Most functions are **pure**; behaviour formulas (`OnSelect`, `OnChange`) are where side effects
  live, and chain with `;`.
- **There is no execution order** between property formulas. If a translation depends on one, the
  original app did not guarantee it either.
- `Set` is global, `UpdateContext` is screen-scoped — the distinction matters when porting state.
- Blank is not null: `IsBlank()` is true for empty string, and `Blank()` propagates through
  arithmetic.

## Naming

- Screens: descriptive and unique.
- Controls: `TypeName` + number as the designer generates them (`Button1`, `Label2`). Renaming
  breaks any formula referencing the old name — search before renaming.
- Components: PascalCase. Custom properties: PascalCase.
- Standard property names use the exact casing from the schema. Casing is not stylistic here; a
  mis-cased property is silently ignored.

## Required properties

A file that omits these will not pack:

- every control needs `Control`
- component definitions need `DefinitionType`
- data sources need `Type`

## Reading a Canvas app for migration

When the goal is a React/Code App port rather than a Canvas edit, behaviour hides in places that are
easy to miss. Check each explicitly:

- `OnVisible` / `OnStart` — initialisation with no obvious React counterpart
- `Visible` and `DisplayMode` formulas — permission logic scattered per control rather than
  centralised
- `Default` and `Reset` — form state behaviour that looks like nothing at all
- Delegation warnings — a query that exceeded the delegation limit silently operated on the first
  500 rows. The faithful port is often **not** the correct one; flag it and confirm which behaviour
  is wanted.

See `canvas-migration-guide` and `parity-auditor` for the translation and verification workflow.
