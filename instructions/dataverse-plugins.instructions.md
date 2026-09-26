---
description: 'Dataverse plug-in and Custom API implementation rules for C# in the sandbox — stage registration, statelessness, error contract. Overrides csharp-dotnet.instructions.md where they conflict. Transaction semantics live in docs/reference/dataverse-transactional-writes.md.'
applyTo: '**/*.cs'
---

# Dataverse plug-ins

**Applies when this `.cs` file is a Dataverse plug-in, Custom API implementation, or a helper
compiled into a plug-in assembly.** If the project has no Dataverse plug-in assembly, ignore this
file and follow `csharp-dotnet.instructions.md` normally.

## This file overrides `csharp-dotnet.instructions.md`

That file describes modern application C#. The plug-in sandbox is a different runtime, and four of
its rules are actively wrong here. **Do not apply them to plug-in code:**

| `csharp-dotnet.instructions.md` says | In the sandbox |
|---|---|
| async/await for data operations, "await all the way up" | `IOrganizationService` is **synchronous**. There is no async SDK surface. Do not introduce `async`/`await`/`Task` in a plug-in |
| Register services with Singleton / Scoped / Transient, `IOptions<T>` | No DI container. Construct what you need inside `Execute` |
| Collection expressions, .NET 8+ features | Plug-ins target **.NET Framework 4.6.2** — verify against the `.csproj` before using any newer syntax |
| Entity Framework patterns | Not available. Data access is `IOrganizationService` only |

If you are unsure whether a language feature is available, read the `TargetFramework` in the
`.csproj` rather than assuming.

## Plug-in instances are reused — keep them stateless

The platform **caches and reuses plug-in instances across invocations, concurrently.** Any instance
field is shared between unrelated users' requests.

```csharp
public sealed class SubmitRequest : IPlugin {
    private Guid _requestId;            // WRONG - leaks across invocations
    private IOrganizationService _svc;  // WRONG - same

    public void Execute(IServiceProvider sp) {
        var svc = ...;                   // right - everything local to Execute
    }
}
```

This is the hardest plug-in bug to find: it needs concurrency to show up, so it passes every test
and every manual trial, then produces one user's data under another user's action in production.
**Constructor parameters are fine** (they are configuration, set at registration); mutable fields
are not.

## Atomicity comes from the registration, not the code

A Custom API's rollback guarantee depends entirely on the stage and execution mode its step is
registered with. **PreOperation, MainOperation and synchronous PostOperation run inside the database
transaction. PreValidation and asynchronous PostOperation do not.**

Identical C# is fully transactional or not transactional at all depending on that setting, and the
happy path is identical either way — so testing does not reveal it.

**Verify the registration; do not assume it.** Read the step in the Plug-in Registration tool or
query `sdkmessageprocessingstep`, and say which stage you confirmed. Full detail, including the
outbox pattern for sends that must not sit inside the transaction:
`docs/reference/dataverse-transactional-writes.md`.

## The shape of a Custom API implementation

Thin shell: load, decide, persist, record. Business rules live in plain testable classes with no SDK
types in their signatures, so the suite runs in milliseconds without an environment.

```csharp
public sealed class SubmitRequest : PluginBase {
    protected override void Execute(ILocalPluginContext ctx) {
        var request = ctx.LoadRequest(ctx.InputId("RequestId"));

        var result = StateMachine.Apply(request, RequestAction.Submit, ctx.RuleContext());
        if (!result.Ok)
            throw new InvalidPluginExecutionException(result.Code);   // stable code, not prose

        ctx.Save(request);
        ctx.History(request, EventCode.Submitted);
        ctx.QueueNotification(NotificationType.Submitted, request);
    }
}
```

- **Throw `InvalidPluginExecutionException` with a short stable code.** Never let an exception carry
  a stack trace to the client, and never return a localised sentence — the client maps codes to
  messages. Adding a code means adding its client mapping in the same change.
- **Catch nothing you cannot handle.** Swallowing an exception inside a transactional stage converts
  a clean rollback into committed bad data. Let it propagate.
- **One exception to that:** an operation whose entire job is to never fail the caller — a
  classifier called by a flow that would otherwise lose the message — wraps every branch and records
  the failure as a row instead. Make that choice explicit in a comment naming why.

## Guard against re-entry

A plug-in that writes to the table it is registered on re-triggers itself. Check the depth and
return:

```csharp
if (ctx.PluginExecutionContext.Depth > 1) return;
```

Prefer not writing to your own table at all: in PreOperation, modify the `Target` entity in the
message rather than calling `Update`.

## Constraints to design around

- **Two-minute execution limit**, and the transaction holds locks for its duration. Long work belongs
  in an asynchronous step or a flow, which means it is outside the transaction — decide deliberately.
- **No third-party assemblies.** Dependencies must be ILMerged, which is a recurring source of
  loader failures. Prefer the SDK and the BCL. If a dependency looks unavoidable, say so and ask.
- **Sandbox isolation**: no file system, no arbitrary outbound network calls. Reaching another system
  means a webhook, an Azure Service Bus endpoint, or the outbox pattern.
- **Register steps only on tables you own.** Two plug-ins from two authors on the same message and
  table produce order-dependent defects that surface far from their cause. If you need behaviour on
  someone else's table, ask them for a helper rather than adding a step.
- **`ITracingService` output only appears in the Plug-in Trace Log**, and only when tracing is
  enabled on the environment. Trace the inputs and the decision, never field values that carry
  personal or confidential data.

## Testing

- Rules in plain classes, tested with xUnit and no environment. Every branch of the state machine
  gets a test that permits it and one that denies it.
- Test the plug-in wrapper against a mocked `IOrganizationService` (FakeXrmEasy or equivalent) —
  enough to prove the code is thrown and the right rows are written.
- **Each error code needs a test that provokes it.** A code nothing produces is a mapping that will
  never be exercised until a user meets it.
