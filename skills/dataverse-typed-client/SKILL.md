---
name: dataverse-typed-client
description: 'TRIGGER - read this BEFORE writing any code that reads or writes Dataverse: before the first call to a generated *Service class, before adding a data hook, and before a component that displays or edits Dataverse records. Do NOT skip because it is "just one query" - a single service call written inline is what the whole query-hook layer exists to prevent. Covers key factories, explicit column lists, paged list hooks, mutations with invalidation, and optimistic-write safety. SKIP when creating the data source itself (use power-apps-code-app-scaffold) or when the project has no src/generated/ directory.'
---

# Dataverse Typed Client

Generated services are a transport layer, not a data layer. This skill builds the layer that should
sit between them and your components.

## When this applies

Use it when you see any of:
- a component calling `SomethingService.getAll()` directly in its body or in a `useEffect`
- raw array literals as query keys (`['accounts']`) scattered across files
- `select` omitted, so a wide Dataverse row is fetched to read two fields
- no pagination on a list that will grow
- a mutation that writes but never invalidates

## Target structure

For an entity `Accounts`, produce `src/features/accounts/api/`:

```
api/
├── keys.ts        # query key factory — the single source of truth for invalidation
├── columns.ts     # explicit column lists (the `select` payload)
├── useAccounts.ts # paged list query
├── useAccount.ts  # single-record query
└── mutations.ts   # create / update / delete + invalidation
```

## Step 1 — Read the generated model first

Never infer the schema. Open `src/generated/models/<Entity>Model.ts` and use the actual field names
and types. Logical names in Dataverse are frequently not what a developer would guess
(`name` vs `accountname`, publisher-prefixed custom columns like `new_status`).

If the model file is missing, the data source was never added — stop and use the
`power-apps-code-app-scaffold` skill instead.

## Step 2 — Column constants

```ts
// columns.ts — every query selects explicitly; never fetch a whole row by default.
export const ACCOUNT_LIST_COLUMNS = ['accountid', 'name', 'statuscode'] as const;
export const ACCOUNT_DETAIL_COLUMNS = [...ACCOUNT_LIST_COLUMNS, 'telephone1', 'revenue'] as const;
```

Separate list and detail column sets. A list view fetching detail columns is the most common cause
of a slow Code App.

## Step 3 — Key factory

```ts
// keys.ts
export const accountKeys = {
  all: ['accounts'] as const,
  lists: () => [...accountKeys.all, 'list'] as const,
  list: (filter: AccountFilter, page: number) => [...accountKeys.lists(), filter, page] as const,
  details: () => [...accountKeys.all, 'detail'] as const,
  detail: (id: string) => [...accountKeys.details(), id] as const,
};
```

Every input that changes the result must be in the key. General → specific ordering so
`invalidateQueries({ queryKey: accountKeys.lists() })` sweeps all list variants without touching
detail caches.

## Step 4 — Query hooks

```ts
export function useAccounts(filter: AccountFilter, page = 0) {
  return useQuery({
    queryKey: accountKeys.list(filter, page),
    queryFn: () => AccountsService.getAll({
      select: [...ACCOUNT_LIST_COLUMNS],
      filter: toODataFilter(filter),
      top: PAGE_SIZE,
      skip: page * PAGE_SIZE,
    }),
    staleTime: 60_000,       // decide per entity — reference data vs operational data differ
    placeholderData: (prev) => prev,  // keeps the table stable while paging
  });
}
```

Set `staleTime` deliberately per entity. Reference/lookup tables tolerate minutes; records users
edit concurrently need seconds or zero.

### `top` is not optional, and "simple request" is not a reason to drop it

**Observed failure.** Asked for "a list of accounts with their name and city", an agent read this
skill, correctly built the feature folder, the key factory and the explicit column list — then called
`getAll({ select })` with no bound, and flattened `list(filter, page)` to `list()`. Its own reasoning:
*"the request is straightforward… following the full architectural conventions goes beyond the simple
scope."*

That trade is backwards. The parts it kept are stylistic; the part it dropped is the one that
decides whether the app works on real data. `getAll()` unbounded pulls **every row in the table** —
on `account` or `contact` in a live tenant that is thousands of records fetched to render twenty,
and it will look perfectly fine against a dev environment holding nine.

So, regardless of how small the request sounds:

- **A list hook without `top` is incomplete.** Not "unoptimised" — incomplete.
- **Include `orderBy`.** Paging over an unordered set can repeat or skip rows between pages.
- **Keep `page` in the key factory** even when the first screen shows one page. Adding it later means
  revisiting every call site and every `invalidateQueries`.
- If you genuinely believe the table is bounded and tiny, say so explicitly and give the reason —
  do not silently omit the bound.

## Step 5 — Mutations

```ts
export function useUpdateAccount() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: UpdateAccountInput) => AccountsService.update(input.id, toDataverse(input)),
    onSuccess: (_data, input) => {
      qc.invalidateQueries({ queryKey: accountKeys.detail(input.id) });
      qc.invalidateQueries({ queryKey: accountKeys.lists() });
    },
  });
}
```

- **Map explicitly** between the app shape and the Dataverse column shape (`toDataverse`). Never pass
  a form object straight through — a renamed field then silently writes the wrong column.
- **Empty optional values are `null`** for Dataverse, not `''` or `undefined`.
- **Optimistic updates need rollback**: snapshot in `onMutate`, restore in `onError`, invalidate in
  `onSettled`. For records multiple users edit, read the `lock-semantics-expert` skill before adding
  optimistic writes at all — a lost update is worse than a slow one.

## Constraints to respect

Generated Dataverse services have **no FetchXML, no polymorphic lookups, no alternate keys, and no
schema refresh**. Design around these rather than working around them:

- Schema changed? `pa app refresh data-source --name <name>`.
- Need a polymorphic lookup (`regardingobjectid`)? Query the concrete entity separately.
- Never hand-edit `src/generated/**` — regeneration overwrites it wholesale.

## Definition of done

- [ ] No component calls a generated `*Service` directly
- [ ] Every query key comes from the factory, no inline literals
- [ ] Every query has an explicit `select` and a deliberate `staleTime`
- [ ] Lists paginate server-side
- [ ] Every mutation invalidates the narrowest key that covers its effect
- [ ] Every mutation surfaces failure to the user
