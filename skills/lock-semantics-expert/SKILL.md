---
name: lock-semantics-expert
description: Reusable patterns for optimistic locking, conflict resolution, retry logic, and concurrent data safety
---

# Lock Semantics Expert

Patterns for concurrent data access, conflict detection, and safe lock management — for any screen
where two users can edit the same record at the same time.

> **This skill is about two users on one row.** If the problem is one user writing **several rows**
> in one action, that is atomicity, not concurrency, and nothing here fixes it — a sequence of
> generated-service calls has no rollback whatever locking you put around it. Go to
> `docs/reference/dataverse-transactional-writes.md` and the `custom-api-authoring` skill instead.
> The two are easy to conflate because both present as "the data ended up wrong".

## When to Use This Skill

- Choosing between optimistic and pessimistic concurrency for an editable record
- Designing conflict resolution (last-write-wins, notify-and-reload, merge)
- Building retry logic for transient failures
- Handling lock lifecycle states — acquired, released, expired, orphaned
- Reviewing an existing implementation for race conditions

## Start by reading, not recommending

Before proposing anything, establish what the project already does:

- Does the update path send a version or timestamp back to the server?
- Is there a lock table in `power.config.json`?
- What does the UI do today when a save is rejected?

Recommendations that assume a greenfield screen are useless on a screen that already has a
half-built locking scheme, and the two combine badly.

## Choose the weakest mechanism that meets the requirement

### Last-write-wins

The default when nothing is implemented. Legitimate for low-contention, low-stakes data — but it
should be a **stated decision**, not an accident. Ask whether a silently overwritten edit is
acceptable here. Often the answer is yes and no further work is needed.

### Optimistic concurrency — the usual right answer

- **Read**: capture the row version (`@odata.etag`, or a `modifiedon` timestamp) alongside the data
- **Write**: send it back with the update so the server rejects a stale write
- **Conflict**: surface it to the user with a real choice — reload and lose edits, or overwrite

No lock to leak, no cleanup path, no orphan states. Costs one field and one error branch.

The failure mode to avoid: capturing the version and then **not** checking it, which looks like
concurrency control in code review and is not.

> ⚠️ **Power Apps Code Apps cannot do the "Write" step.** Verified in `@microsoft/power-apps`:
> `updateRecordAsync(tableName, recordId, changes)` takes three arguments and **no options object**,
> so there is no `If-Match` header and no way to have Dataverse reject a stale write. The generated
> services expose nothing else either.
>
> What is achievable there is **read-before-write**: capture `modifiedon` when the record loads,
> re-read it immediately before saving, compare, and stop on a difference. **Say explicitly that this
> narrows the race window rather than closing it** — two writes inside the gap between the re-read
> and the update still collide. Presenting it as a guarantee is the real danger, because the code
> looks identical to the server-enforced version.
>
> A hard guarantee requires moving the write server-side into a custom Dataverse action or plugin.
> Recommend that only when the domain genuinely demands it.
>
> Found on 2026-08-03: this skill previously gave the "send the etag back" advice unconditionally in
> a Power Apps baseline, where it cannot be followed. Generic concurrency advice is not automatically
> portable — check what the client actually exposes before prescribing a mechanism.

### Pessimistic locking — only when exclusivity is a domain requirement

Justified when concurrent editing is genuinely unacceptable — a long multi-step form where losing
work is severe, or a workflow where two in-flight edits corrupt downstream state.

It costs you every one of these, and each needs an answer before you start:

- **Orphaned locks.** The browser crashes mid-edit. Who releases it? An expiry is mandatory, not
  optional.
- **Release on exit.** Unmount handles navigation. `beforeunload` is unreliable and not guaranteed to
  complete a network request — treat it as best-effort and rely on expiry as the real guarantee.
- **Acquire races.** Two users click Edit simultaneously. Acquisition must be atomic server-side; a
  read-then-write in the client is not.
- **The waiting user.** What do they see? "Locked by someone else" with no name and no expiry time is
  a support ticket.

A lock does **not** remove the need for a version check. The record can still change between
acquiring the lock and saving, if any other path writes to it.

## Lock lifecycle

```
[NO_LOCK]
  ↓ user begins editing
[ACQUIRING]
  ↓ server confirms
[LOCKED] ──── expiry elapsed ────→ [EXPIRED] → treat as NO_LOCK on next action
  ↓ save or cancel
[RELEASING]
  ↓
[NO_LOCK]

Edge cases that need explicit handling:
- ACQUIRING → FAILED        another holder; show who and until when, offer read-only
- LOCKED    → STALE         record changed anyway; version check still applies
- LOCKED    → unmount       release immediately, do not await
- EXPIRED   → save attempt  reject; the user must re-acquire
```

## Retry

Retry **transient** failures only — network errors, timeouts, throttling. Never retry a conflict:
a stale-version rejection will fail identically every time and the retry only delays the message.

```typescript
async function withRetry<T>(op: () => Promise<T>, attempts = 3): Promise<T> {
  let lastError: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await op();
    } catch (err) {
      if (!isTransient(err)) throw err;   // conflicts and 4xx fail fast
      lastError = err;
      await new Promise(r => setTimeout(r, 2 ** i * 200));
    }
  }
  throw lastError;
}
```

Cap total elapsed time, not just attempt count — four exponential retries on a 30s timeout is two
minutes of a spinner.

## Conflict UX

When a conflict is detected, the user needs to know **what** changed, not just that something did.
"This record was changed by someone else — reload?" discards their work with no information.

In order of increasing effort:

1. Reload, showing which fields differ from what they had
2. Field-level merge for non-overlapping edits — safe when two users touched different fields
3. Full merge UI — rarely worth it

Rows are easier than fields: inserts never conflict, so an add-row grid can often merge cleanly where
a shared form cannot.

## Integration points

Locate these in the project rather than assuming paths:

- The hook owning the edit lifecycle for the record
- The service layer wrapping the generated Dataverse client
- The types carrying the version/etag through the flow
- The permission check that gates whether editing is offered at all

## Reference

- `data-fetching.instructions.md` — cache invalidation after a conflict-driven reload
- `power-apps-code-apps.instructions.md` — Dataverse concurrency constraints in a Code App
- `error-handling.instructions.md` — surfacing a conflict without an empty iframe
