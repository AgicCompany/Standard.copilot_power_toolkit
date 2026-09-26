---
description: 'Form conventions — react-hook-form + Zod, one schema per form, and the Dataverse write path.'
applyTo: '**/*.{ts,tsx}'
---

# Forms and Validation

**react-hook-form + Zod.** Uncontrolled inputs via RHF, validation via a Zod schema, wired with
`zodResolver`. Do not hand-roll `useState`-per-field forms, and do not add Formik or Yup.

## One schema, one source of truth

```ts
// features/accounts/schema.ts
export const accountFormSchema = z.object({
  name: z.string().min(1, 'Name is required').max(160),
  email: z.string().email('Enter a valid email').optional().or(z.literal('')),
  revenue: z.coerce.number().nonnegative().optional(),
});

export type AccountFormValues = z.infer<typeof accountFormSchema>;
```

- **Never declare a form's TypeScript type by hand** — infer it from the schema with `z.infer`. Two
  hand-maintained declarations drift.
- **Validation rules live in the schema, not in JSX.** No `required` attribute doing the real work
  while the schema says the field is optional.
- **`z.coerce`** for anything arriving from an input as a string but stored as a number/date.

## Rules

- **Validate on submit; re-validate on change once a field has errored.** Validating every keystroke
  from the start punishes users mid-typing.
- **Disable submit while `isSubmitting`** and show progress. A double-submitted Dataverse create
  makes duplicate records.
- **Server errors map back onto fields** with `setError(fieldName, …)` where the API identifies one;
  otherwise show a form-level error. Never swallow a failed write.
- **Reset with `reset(serverValues)` after a successful save**, so `isDirty` is accurate and the
  unsaved-changes guard stops firing.
- **Warn on navigation away while `isDirty`.**

## Accessibility

Non-negotiable, and it is the most commonly broken part of a form:

- Every field has a real `<label htmlFor>` — placeholders are not labels.
- Errors are linked with `aria-describedby` and the field carries `aria-invalid`.
- On failed submit, **focus the first invalid field** and render an error summary.
- Required state is conveyed in text, not by colour or a bare asterisk.

With shadcn/ui, the `Form`/`FormField`/`FormMessage` primitives wire `htmlFor`, `aria-describedby`,
and `aria-invalid` for you — **use them rather than composing raw `Input` + `Label`**, which is where
this usually breaks.

## Dataverse writes

- The **form schema is not the Dataverse column shape.** Map explicitly in the mutation, so
  renaming a form field never silently writes the wrong column.
- Validate against real column constraints — max lengths, option-set values, required-on-create —
  rather than discovering them as a 400 at runtime. The `dataverse-schema-validator` skill checks
  this against `power.config.json`.
- Optional-but-empty is `null` for Dataverse, not `''` or `undefined`. Normalise before writing.
