---
name: dataverse-schema-validator
description: Validate entity relationships, required fields, option sets against power.config.json—catch schema drift before runtime
---

# Dataverse Schema Validator

Validate Dataverse schema integrity against what the app actually generated, so drift surfaces at
review time instead of as an empty grid in production.

## When to Use This Skill

- Validating entity relationships and column definitions against `power.config.json`
- Checking for drift between Dataverse metadata and the generated TypeScript types
- Identifying missing required fields or incorrect option set values
- Confirming lookup cardinality (1:N, N:N) matches what the code assumes
- Auditing a new data source before wiring it into a screen

## The drift that actually bites

Generated services do not track schema changes on their own. When a table changes in Dataverse, the generated
types keep describing the old shape and TypeScript keeps compiling. The fix is
`pa app remove data-source` followed by `pa app add data-source` — but nothing prompts you,
which is exactly why an explicit check is worth running.

Symptoms that mean "regenerate" rather than "debug my code":

- A column exists in Dataverse and is absent from `src/generated/models/`
- A query returns rows with `undefined` for a field that definitely has data
- An option set value is rejected that the maker portal clearly shows

## Validation areas

### 1. Entity structure
- **Column types** match between Dataverse and the generated model — a Decimal typed as `string`
  compiles fine and breaks on arithmetic
- **Required columns** are known, so a create call does not fail at runtime
- **Option sets**: the numeric values, not just the labels. Labels are localised; values are the
  contract
- **Calculated and rollup columns** are read-only — writing to them fails silently or errors
  depending on path

### 2. Relationships
- **1:N lookups** — confirm the direction. The lookup column lives on the *many* side
- **N:N** — junction tables; confirm whether the generated service exposes the relationship at all
- **Polymorphic lookups** (`Customer`, `Owner`, `Regarding`) are **not supported** by generated
  services. If the schema has one, that is a design constraint to surface immediately, not a bug
- **Cascade behaviour** on delete, and whether the child inherits the parent's row-level security

### 3. Query safety
- **OData filter syntax** validated against the actual column names — `$filter` on a column that
  does not exist returns an error, but `$select` of a missing column can return silently incomplete
  rows
- **No FetchXML.** Generated Code App services do not support it. If a validation would require
  FetchXML — aggregation, `link-entity` joins, grouping — say so and propose the OData reshape, a
  rollup column, or a server-side flow instead
- **No alternate keys.** Retrieval is by primary key
- Columns used in filters and sorts on large tables should be indexed

### 4. Generated services alignment
- Do the types in `src/generated/models/` match the entities in `power.config.json`?
- Do service method signatures expect the shapes the calling code passes?
- Are nullable columns typed as optional?

## Process

**Step 1 — Read the three sources.** `power.config.json` (what is bound), `src/generated/`
(what the app can see), and — if migrating — `canvas_src/DataSources/*.json` (what the Canvas app
expected). Do not proceed on a described schema; read the files.

**Step 2 — Compare.** Missing columns in generated types; lookup targets that do not resolve; option
set values that differ from the Canvas source; required columns absent from create paths.

**Step 3 — Report concretely.** Name the column, both types, and the fix:

> `<column>` is Decimal in Dataverse but typed `string` in the generated model — regenerate the data
> source; arithmetic on this field is currently string concatenation.

> Lookup target changed from `<old>` to `<new>` — this is a breaking change; every query filtering on
> the old target returns empty rather than erroring.

State clearly when a mismatch is a **platform limitation** rather than a defect, so nobody spends a
day working around polymorphic lookup support that does not exist.

## Example scenarios

**Adding a data source**
1. Confirm the entity's schema and required columns
2. Check lookup cardinality and direction against how the screen intends to query it
3. Flag any polymorphic lookup or alternate-key dependency now
4. Confirm the generated service exposes the type after `pa app add data-source`

**Query returns empty but data exists**
1. Validate the OData filter against actual column names
2. Check lookup navigation direction — filtering the wrong side is the most common cause
3. Verify row-level security: does the current user have read access to those rows?
4. Confirm the generated types are not stale — the fastest check is whether a column added recently
   appears in `src/generated/models/`

## Integration points

- **power.config.json** — source of truth for bound entities
- **src/generated/** — TypeScript contracts; regenerate rather than edit
- **canvas_src/DataSources/*.json** — legacy schema, when migrating
- **`<pm> run build`** — catches type mismatches, but only those the stale types already describe
