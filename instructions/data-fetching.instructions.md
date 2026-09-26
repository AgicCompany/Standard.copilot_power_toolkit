---
description: 'Server-state conventions — TanStack Query for anything that came from a server. Query keys, cache policy, mutations, and the useEffect-fetching ban.'
applyTo: '**/*.{ts,tsx}'
---

# Data Fetching (TanStack Query)

**TanStack Query owns all server state.** `useState` + `useEffect` fetching is not an acceptable
alternative — it re-implements caching, deduplication, cancellation, and retry, badly.

Client state (form drafts, open/closed, selection) stays in `useState`. The distinction is: *did
this come from a server?* If yes, it belongs to Query.

## The wrapping rule

**No data source is called from a component body** — not `fetch`, not an SDK client, not a generated
service. Every one gets a hook in `features/<name>/api/` that wraps it in a query:

```ts
// features/accounts/api/useAccounts.ts
export const accountKeys = {
  all: ['accounts'] as const,
  list: (filter: AccountFilter) => [...accountKeys.all, 'list', filter] as const,
  detail: (id: string) => [...accountKeys.all, 'detail', id] as const,
};

export function useAccounts(filter: AccountFilter) {
  return useQuery({
    queryKey: accountKeys.list(filter),
    // top bounds the result; orderBy makes paging stable. Neither is optional.
    queryFn: () => AccountsService.getAll({
      select: ACCOUNT_COLUMNS, filter, orderBy: ['name asc'], top: PAGE_SIZE,
    }),
    staleTime: 5 * 60_000,
  });
}
```

## Query keys

- **Every feature exports a key factory** like `accountKeys` above. Never inline a raw array literal
  at a call site — invalidation then depends on two places agreeing on a string.
- **Keys include every input that changes the result** (filter, page, sort, id). A key missing an
  input serves stale data for the wrong query.
- Order keys **general → specific** so `invalidateQueries({ queryKey: accountKeys.all })` sweeps the
  whole feature.

## Cache policy

- **`staleTime` is a decision, not a default.** Set it per query: reference/lookup data that changes
  rarely gets minutes; operational data that others edit concurrently gets seconds or zero.
- Do not set a global `staleTime: Infinity` — it hides real staleness bugs until a user complains.
- **`enabled`** for dependent queries. Never fetch with a placeholder id and discard the result.

## Mutations

- **Every mutation invalidates what it affected** in `onSuccess` — the narrowest key that covers it.
- **Optimistic updates require a rollback.** Snapshot in `onMutate`, restore in `onError`,
  invalidate in `onSettled`. An optimistic update without rollback shows the user a lie when the
  write fails. For Dataverse specifically, concurrent edits are common — see the
  `lock-semantics-expert` skill before adding optimistic writes to shared records.
- **Surface mutation errors in the UI.** A failed write that only logs to console is a data-loss bug.

## Dataverse specifics — only if this project has `src/generated/services/`

**Check before applying any of this.** This file ships to plain React projects too, where there is no
Dataverse, no generated services and no `src/generated/`. Offering them as an option there invents a
data source that does not exist — confirmed live: asked to load a list from an API in a bare Vite
project, a model's first clarifying question offered *"a Dataverse generated service
(`src/generated/services`)"* as one of two choices. Everything above this heading is stack-neutral
and always applies; everything below is conditional on that folder existing.

- **Always `select` an explicit column list.** Never fetch a whole wide table row to read two fields.
- **Page server-side** (`top`/`skip`); never fetch everything and slice client-side.
- **Parallelise independent queries** — separate `useQuery` calls run concurrently; sequential
  `await`s in one `queryFn` do not.
- Generated services have no FetchXML, no polymorphic lookups, and no alternate keys. Design the
  query around that rather than working around it.
