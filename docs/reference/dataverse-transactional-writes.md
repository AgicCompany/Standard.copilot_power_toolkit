# Transactional writes in a Code App

Read this when one user action has to change **more than one row**. The generated Dataverse services
cannot do that safely, and the failure is silent: you get half the write, no error the user can act
on, and data that looks fine until someone reconciles it weeks later.

Loaded on demand. The rule that decides *when* to come here lives in
`power-apps-code-apps.instructions.md`.

## The problem

Each generated service call is its own HTTP request and its own transaction. A sequence of them in
one handler is a sequence of independent commits:

```ts
// WRONG - four commits, no atomicity
const request = await RequestsService.create(header);        // committed
await RequestLinesService.create(lines, request.id);          // committed
await AssetsService.update(assetId, { status: 'Reserved' });  // FAILS HERE
await AuditService.create({ action: 'Submitted' });           // never runs
```

When line 3 throws you are left with a request and its lines committed, the asset unreserved, and no
audit row. **`try/catch` does not help you.** Catching the error tells you something failed; it does
not give you a way to undo the two commits that already succeeded. Compensating by hand — deleting
the rows you just wrote — is itself a sequence of un-guaranteed writes, and it runs at exactly the
moment the network or the server is already misbehaving.

There is no client-side transaction, no batch-with-rollback, and no `$batch` support in the
generated services. This is not a gap in your code.

## The decision test

**More than one row written in one user action → the write moves server-side into a Custom API.**

Apply it mechanically, not as a judgement call:

| Writes in one user action | Where it goes |
|---|---|
| One row, one table | Generated service, called from a mutation hook |
| One row + its own audit/history row | Custom API |
| Two or more tables | Custom API |
| One row, but a status elsewhere depends on it | Custom API |
| Anything a second user could interleave with | Custom API |

**What to do instead when a Custom API is not available to you** — no C# in the project, no plug-in
registration rights, a hard deadline: say so explicitly to the user and name the exposure. "These
three writes are not atomic; if the third fails the first two stand, and nothing will detect it"
is a decision they can make. Writing the sequence and staying quiet is not.

Do not reach for a compensating-delete "rollback" in the client as a substitute. It doubles the
number of writes that can fail and creates a second, worse failure mode: a partial undo.

## What a Custom API actually guarantees — and what it does not

A Custom API is a Dataverse message backed by a plug-in. Inside that plug-in, every write you make
through `IOrganizationService` joins **one database transaction**, and throwing rolls all of it back.

**That guarantee comes from how the step is registered, not from the code you write.** Identical C#
is fully atomic or not atomic at all depending on a dropdown in the registration tool.

| Stage | In the database transaction? | Use it for |
|---|---|---|
| **PreValidation** (10) | **No** — runs before the transaction opens | Cheap rejections before any work starts. Also runs before security checks |
| **PreOperation** (20) | **Yes** | Changing values on the row in the message |
| **MainOperation** (30) | **Yes** | **Custom API implementations register here** |
| **PostOperation** (40), synchronous | **Yes** | Writing related rows, history, queue entries |
| **PostOperation** (40), **asynchronous** | **No** — runs later, outside the transaction | Work that is genuinely allowed to fail independently |

Microsoft states it directly: *"An exception thrown by your code at any synchronous stage within the
database transaction causes the entire transaction to roll back."*

The two ways to believe you have atomicity and not have it:

- **The step is registered asynchronous.** The API returns success, the writes happen later, and a
  failure leaves partial data with the only trace in the system job list.
- **The logic sits in PreValidation.** It runs before the transaction opens, so writes made there
  are not rolled back by a later failure.

**Verify the registration rather than assuming it.** Open the step in the Plug-in Registration tool
(or query `sdkmessageprocessingstep`) and confirm the stage and the synchronous execution mode
before claiming the operation is transactional. A plug-in that "works" in testing proves nothing
about this — the happy path is identical either way.

## Custom API configuration

| Setting | Choose | Why |
|---|---|---|
| Binding Type | **Global (unbound)** unless you need the row context | The generated TypeScript is simpler: unbound methods take only the declared parameters, bound ones take a record id as the mandatory first argument |
| Is Function | **No** for anything that writes | Functions are GET and cannot have side effects |
| Is Function | **No** for anything taking a string parameter — see below | |
| Enabled for Workflow | **No** | Keeps the operation out of classic workflows |
| Allowed Custom Processing Step Type | **None** | Stops third-party plug-ins hooking your business logic |

### A Function cannot take a JSON parameter

`Is Function: Yes` exposes the message over **GET**, so every input travels in the URL path. Dataverse
rejects string parameter values containing `/ < > * % & : \ ? +` with **HTTP 400** unless the caller
uses parameter aliases.

**JSON always contains `:`.** A read-only operation taking a `FiltersJson` or similar payload will
therefore fail the moment a real filter is passed, while testing clean with an empty one.

- Read-only operation, no parameters or only GUIDs/numbers → Function is fine.
- Read-only operation taking a string or JSON payload → **make it an Action.** Parameters travel in
  the POST body, where no encoding rule applies. Losing GET caching is worth it.

Complex types are not supported as Custom API parameters at all — pass JSON strings and parse
server-side. The generated client surfaces complex and table returns as
`Promise<IOperationResult<Record<string, unknown>>>`, so type them at the boundary yourself.

## The error contract

The plug-in throws `InvalidPluginExecutionException` carrying a **stable, short code**. The client
maps the code to a message. Do not send a sentence from the server and render it; do not send a
stack trace at all.

```csharp
if (!result.Ok)
    throw new InvalidPluginExecutionException(result.Code);   // "REQUEST_READONLY"
```

```ts
const ERRORS: Record<string, string> = {
  REQUEST_READONLY: 'This request is closed and can no longer be changed.',
  TRANSITION_NOT_ALLOWED: 'That action is not available from the current status.',
};
// unknown code -> a generic message, and log the raw code
```

Why it is worth the indirection: the codes are testable from C# without a browser, they survive
translation, and they let the client distinguish "show this inline on the field" from "show a
dialog" without parsing prose. Pair each code with a test that provokes it.

**If you add a code, add its client mapping in the same change.** A code with no mapping renders as
the generic fallback, which reads to the user as a bug with no cause.

## The outbox pattern

Sending an email, calling a webhook or posting to Teams inside the transaction is wrong twice over:
the send is not rolled back if the transaction later fails, and an outage in the other system fails
a database write that had nothing to do with it.

Write a **row** instead, in the same transaction:

```
Plug-in (synchronous, in transaction)
  ├─ writes the business rows
  └─ writes app_outboundmessage { status: Pending, type, payload }
        ↓  transaction commits (or rolls back, taking the queued message with it)
Dispatcher flow (scheduled)
  └─ picks up Pending rows, sends, marks Sent or Failed with a retry count
```

The queued message commits or vanishes with the data it describes — you cannot notify someone about
a status change that got rolled back. Retries become a property of the dispatcher, and a failed send
is a row you can query rather than a run-history entry nobody reads.

Give the dispatcher a **uniqueness key** and a bounded retry count. Without the key a resubmission
sends twice; without the bound a permanently failing message is retried forever.

## Things that look like solutions and are not

- **`try/catch` around the sequence.** Reports the failure, cannot undo the commits.
- **Reversing the writes in the `catch`.** A second un-guaranteed sequence, run under bad conditions.
- **Ordering the writes so "the important one goes first".** Reduces how bad the inconsistency is;
  it does not make the operation atomic, and it hides the problem from testing.
- **A Power Automate flow doing the steps.** A flow is not a transaction. A failure mid-flow leaves
  the earlier actions applied. Flows are the right home for the *dispatcher*, not for the write.
- **Optimistic concurrency.** Different problem — two users on one row, not one user across many
  rows. See the concurrency section of `power-apps-code-apps.instructions.md`.

## Related

- `instructions/dataverse-plugins.instructions.md` — writing the C# itself
- `skills/custom-api-authoring/` — the end-to-end walkthrough, CLI included
- `instructions/power-apps-code-apps.instructions.md` — the client half
