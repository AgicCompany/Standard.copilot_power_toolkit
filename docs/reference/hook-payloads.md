# Hook Payloads — What The Host Actually Sends

**Status: RESOLVED for VS Code Copilot Chat (captured 2026-07-27).** Read this before writing or
debugging a hook script that parses its input.

## Available events

The full authoring guide (`instructions/hooks.instructions.md`) ships only with the
`baseline-authoring` profile — but **hooks ship with every project**, so the event list lives here
too. Without it, anyone debugging a hook in an app project has no reference at all.

| Event | stdout | Typical use | Fires in VS Code Chat? |
|---|---|---|---|
| `sessionStart` | **parsed** — `additionalContext` is injected, but ONLY in the nested shape below | Setup, context injection | ✅ verified working 2026-08-01 |
| `userPromptSubmitted` | ignored | Auditing, prompt blocking | ✅ verified |
| `preToolUse` | **parsed** — `permissionDecision`, `additionalContext` | Guardrails, deny/block | ✅ verified (deny confirmed working) |
| `PostToolUse` | ignored | Logging, formatting | ✅ **verified — PascalCase only**; camelCase `postToolUse` does NOT fire |
| `sessionEnd` | ignored | Cleanup, summaries | ❌ **never fires** — probe-verified, incl. full VS Code quit |
| **`Stop`** | — | **Turn complete** — best home for end-of-change checks | ✅ **verified, fires every turn** |
| `agentStop` / `AgentStop` | — | Documented for end-of-turn checks like `git diff --stat`. Not re-probed here, because `Stop` already covers the use case | ❓ **untested** |
| `postToolUseFailure` | — | Recovery after a failed tool run | ❓ untested |
| `subagentStart` / `subagentStop` | — | Subagent audit / output validation | ❓ untested |
| `errorOccurred` | ignored | Diagnostics, alerts | ❓ untested |
| `preCompact` | — | Pre-compaction work | ❓ untested |
| `permissionRequest` | — | Approval workflow | ❓ untested |

## `additionalContext` must be NESTED — the flat shape is silently discarded

**This is the single highest-value fact in this file.** Emit exactly this:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "text the model will see"
  }
}
```

A flat `{ "additionalContext": "..." }` is **accepted, raises no error, produces no warning, and is
thrown away.** The hook runs, exits 0, logs success, and the model never sees a word of it.

`hookEventName` must match the event: `SessionStart`, `PreToolUse`, and so on.

Spec: <https://code.visualstudio.com/docs/agent-customization/hooks>

### How this was found, and what it cost

Every context-injecting hook in this baseline used the flat shape and had therefore **never worked,
in any project.** On 2026-08-01 that produced a full day of wrong conclusions:

1. `dataverse-schema-drift` logged `emitted_drift_warning` on every run while Copilot showed no sign
   of it. Asked directly, Copilot enumerated its starting context and confirmed nothing arrived.
2. From that, this file was edited to claim `additionalContext` **is not delivered on this host** —
   and, after a `preToolUse` probe failed the same way, that *"a hook can block and log, but it
   cannot tell."*
3. Both claims were **wrong**. Reading the actual spec took two minutes and showed the payload shape.
   Fixed, the drift warning surfaced on the very next run — Copilot opened with *"...and look into
   the schema drift issue that's been flagged"*, unprompted.

The evidence had been sitting in `guard-vite-env.ps1` the whole time: its **deny** path emitted the
correct nested shape and worked, while its **warn** path in the same file emitted flat and did not.
That single file was the control experiment, and nobody read it as one.

**The lesson worth more than the fix:** three failed experiments plus a plausible mechanism is not a
finding. When something documented as working does not work, read the spec before concluding the
platform is at fault. `lint-baseline.ps1` now enforces the nested shape so this cannot regress.

### Downstream effect: the repo memory file started being used

`memory-reminder` was one of the hooks carrying the flat payload, so it had **never** reached the
model in any project. Meanwhile `instructions.instructions.md` and `AGENTS.md` both recorded, as a
known instruction failure:

> `Append durable facts to .github/docs/project-memory.md.` → wrote to its own built-in memory tool

Within two days of the payload fix, Copilot began referencing the file unprompted (*"There's a
recorded entry in project-memory.md I haven't read yet"*) and then **wrote to it for the first time**
during the D8 acceptance step.

That suggests the documented failure was not simply an ignored instruction — it was an instruction
competing against **silence**, while the model's own built-in memory was present and demonstrably
worked. One instance is not proof, so the example stands; but if repo-memory writes keep happening,
revisit it, because "the model ignores this instruction" and "nothing ever told the model the file
was real" call for opposite fixes.

Related: `apply-baseline -Force` was separately overwriting `.github/docs/project-memory.md` on every
re-sync. That bug was **latent** rather than destructive precisely because nothing had ever written
to the file. Both are fixed; either alone would have left the memory mechanism useless.

### Delivery is reliable; volunteering is not

Once correctly shaped, all three context hooks (`dataverse-schema-drift`, `branch-guard`,
`memory-reminder`) verifiably reach the model. Whether the model *raises* the content unprompted
varies: on one `hi` it volunteered the drift warning immediately; on another it surfaced all three
only when asked "is there anything you need to tell me?".

**That is not a bug.** Injected context is present either way. Judge a context hook by whether it
changes behaviour during the work it concerns — which is what the D5 acceptance step measures — not
by whether it appears in a reply to "hi".

### Write the message as a GATE, not an advisory

Measured A/B on 2026-08-01. Same hook, same delivery, same context. **Only the wording changed, and
the behaviour inverted.**

| Wording | What the model did |
|---|---|
| "*offer to* move this onto a branch" / "raise it once, not every turn" / "*If* data access misbehaves this session" | Read it, treated it as background, created files on the protected branch, mentioned it only when challenged afterwards |
| "**STOP - ACT ON THIS BEFORE YOUR FIRST EDIT. This is a gate, not background information.**" + "raise it in your FIRST reply, before doing any of the work" + "telling them afterwards is worthless" | Opened with both warnings, made no edits, and explicitly waited for a decision |

Asked why it ignored the first version, the model's own account was exact: *"a sequencing failure - I
let 'answer the request' outrank 'surface the blocker first'."* Advisory phrasing does not lose
because the model is careless; it loses because answering the question is the task and everything
else reads as optional colour.

So, for any hook or instruction meant to change what happens **before** work starts:

- Open with the gate. Do not bury it after context.
- Say **when** to raise it — "in your first reply, before any edit" — not just *that* it matters.
- Say what the unacceptable outcome is: doing the work and mentioning it afterwards.
- Give the escape hatch, so it stops once the user has decided. That is what prevents nagging —
  **not** softening the language, which was the mistake in the first version.

> ⚠️ **A log line saying `sessionEnd` is not evidence that `sessionEnd` fired.** `session-logger.json`
> registers the *same* script on both `sessionEnd` and `Stop`, and until 2026-07-28 that script
> hardcoded `event: 'sessionEnd'` while discarding the payload. Every `Stop` was therefore recorded
> as a `sessionEnd`. An audit read those 7 entries and "discovered" that `sessionEnd` works —
> overturning a correct, probe-verified finding on the strength of the script's own bad bookkeeping.
> The script now takes its label from `hook_event_name` and writes `unknown` if the payload has no
> such field. **Before concluding an event fires, confirm the logger derives its label from the
> payload rather than from which file it happens to live in.**

**`agentStop` is a real, documented event with its own payload** (`{ timestamp, cwd }`) — the
authoring guide explicitly suggests it for final validation. If it fires here it is a *better* home
for `build-gate` than `sessionEnd`, because the gate would run when a turn completes rather than
whenever a session happens to end. That slot is now filled by `Stop`, which is verified to fire after
every turn; `agentStop` itself has not been re-probed. `docs/reference/event-probe.md` is the procedure
if it ever needs to be.

## The two dialects

**VS Code Copilot Chat** sends snake_case, and `tool_input` is a real **object**:

```json
{
  "timestamp": "2026-07-27T09:34:44.196Z",
  "hook_event_name": "PreToolUse",
  "session_id": "5ffeee5f-…",
  "transcript_path": "…/GitHub.copilot-chat/transcripts/5ffeee5f-….jsonl",
  "tool_name": "create_file",
  "tool_input": { "filePath": "c:\\…\\src\\hello.ts", "content": "export function hello() …" },
  "tool_use_id": "call_…__vscode-…",
  "cwd": "c:\\…\\my-project"
}
```

**GitHub Copilot CLI** (what the official reference documents) sends camelCase, and `toolArgs` is a
JSON **string** needing a second parse:

```json
{ "toolName": "edit", "toolArgs": "{\"path\":\"src/a.ts\",\"content\":\"…\"}" }
```

| | VS Code Chat | Copilot CLI |
|---|---|---|
| Tool name | `tool_name` | `toolName` |
| Arguments | `tool_input` (**object**) | `toolArgs` (**JSON string**) |
| Event name | `hook_event_name` (`"PreToolUse"`) | — |
| Also present | `session_id`, `cwd`, `tool_use_id`, `transcript_path` | — |

Observed `tool_name` values in VS Code Chat: `create_file`, `run_in_terminal`.

**Every script in `hooks/scripts/` now checks both dialects.** Do the same in anything new:

```powershell
if ($payload.PSObject.Properties.Name -contains 'tool_input' -and $payload.tool_input) {
  $parsedArgs = $payload.tool_input                      # VS Code - already an object
} elseif ($payload.toolArgs) {
  $parsedArgs = $payload.toolArgs | ConvertFrom-Json     # CLI - JSON string
}
```

Argument keys also vary — check `filePath`, `path`, `file_path`, `uri`, `targetFile`, `fileName`
for paths, and `content`, `new_str`, `newText`, `text`, `code` for content.

## Response format — CONFIRMED WORKING (2026-07-27)

**A `preToolUse` deny genuinely blocks the tool call in VS Code Copilot Chat, and the reason reaches
the model.** Verified live: asked to create `.env.local` with `VITE_API_KEY=test123`, the write was
refused and Copilot reported *"this workspace has a safety guardrail that blocks VITE_-prefixed
values that look like credentials"* — quoting the script's own reason text — then offered safe
alternatives.

So hooks are real enforcement in this host, not just logging. Note the division of labour that
produced the block: the model had **read** `vite-env-and-secrets.instructions.md` and proceeded
anyway (reasonably — `test123` isn't obviously a secret). The instruction handled judgement; the
hook handled the mechanical rule.

Because the scripts emit both envelopes, **which one the host honours is still unknown** — don't
remove either without re-testing.

The scripts emit **both** envelopes so either parser finds what it expects:

```json
{
  "permissionDecision": "deny",
  "permissionDecisionReason": "…",
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "…"
  }
}
```

Which one VS Code Chat honours has **not** been confirmed — verify by attempting a blocked write and
checking whether it is actually refused, not by reading the log.

## The problem this documents

Every hook script in this baseline parses the payload shape from the **GitHub Copilot CLI** hooks
reference:

```json
{ "toolName": "bash", "toolArgs": "{\"command\":\"ls -la\"}" }
```

`toolArgs` is a JSON **string**, requiring a second parse. That shape is documented and correct for
the CLI.

**It has never been verified against VS Code Copilot Chat.**

## Confirmed live (2026-07)

`tool-guardian` ran on `preToolUse` for several days in VS Code Copilot Chat and logged
**`guard_passed` 200+ times with `"tool":""`** — an empty `toolName` on every single call.

That means one of:

- the payload does not use `toolName` / `toolArgs` in this host,
- the payload is not JSON,
- or nothing is delivered on stdin at all.

Consequences, all silent:

| Hook | Effect |
|---|---|
| `tool-guardian` | matched its threat regex against an empty string, so every command "passed" |
| `vite-env-guard` | found no file path, exited 0 — a live-format API key was written to `.env.local` unblocked |
| `lint-fix-on-edit` | found no file path, exited 0 |

**A guard that cannot read its input must never log success.** These scripts now emit
`guard_no_payload` / `guard_unparsed_payload` instead. False assurance is worse than an obviously
dead hook, because the log looks healthy.

## How to determine the real shape

Drop these two files into a project temporarily, reload, ask Copilot to write any file, then read
`logs/copilot/payload-capture.jsonl`.

`.github/hooks/payload-capture.json`:

```json
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "type": "command",
        "powershell": ".github/hooks/scripts/capture-payload.ps1",
        "bash": ".github/hooks/scripts/capture-payload.sh",
        "cwd": ".",
        "timeoutSec": 10
      }
    ]
  }
}
```

`.github/hooks/scripts/capture-payload.ps1`:

```powershell
$raw = [Console]::In.ReadToEnd()
try {
  if (-not (Test-Path -LiteralPath 'logs/copilot')) {
    New-Item -ItemType Directory -Path 'logs/copilot' -Force | Out-Null
  }
  [System.IO.File]::AppendAllText('logs/copilot/payload-capture.jsonl',
    "[len=$($raw.Length)] $raw" + [Environment]::NewLine)
} catch { }
exit 0
```

`.github/hooks/scripts/capture-payload.sh`:

```bash
#!/usr/bin/env bash
mkdir -p logs/copilot
cat >> logs/copilot/payload-capture.jsonl
exit 0
```

**Delete both files afterwards** — this logs every payload verbatim, including file contents and any
secret passing through a tool call.

### Reading the result

| What you see | Meaning |
|---|---|
| `[len=0]` on every line | stdin is not used by this host — hooks must get input another way (argv/env), and every parsing script needs rewriting |
| JSON with different field names | record them below and update every script's key list |
| The documented `toolName`/`toolArgs` | the CLI shape is right and the bug is elsewhere |

## Rules for hook scripts until this is settled

1. **Never gate on `toolName`.** Names differ per host and version. Filter on the target path or file
   extension — those are stable.
2. **Never use a host-level `matcher`.** It filters on tool name before your script runs, so a
   mismatch disables the hook silently. `lint-baseline.ps1` errors on this for `preToolUse`.
3. **Check several key spellings** for paths (`path`, `file_path`, `filePath`, `uri`, `targetFile`,
   `fileName`) and content (`content`, `new_str`, `newText`, `text`, `code`, `contents`).
4. **Fail loudly when the payload is unusable** — log a distinct event, never a pass.
5. **Set `$PSNativeCommandUseErrorActionPreference = $false`** in any `.ps1` that shells out. See
   below. `lint-baseline.ps1` errors if you forget.

## PowerShell 7.3+ turns a native command's exit code into a terminating error

**Verified live on PowerShell 7.6.3 (2026-07-27).** Under `$ErrorActionPreference = 'Stop'`, a native
command exiting non-zero now raises a **terminating** error. `2>$null` suppresses the stderr *text*
but does nothing about the *exit code*, so the script dies at the call site — before reaching its own
`$LASTEXITCODE` check.

This silently disabled three hooks at once, and a non-zero exit was the **normal, expected signal**
each of them existed to read:

| Script | Call | Exit | What it should have done |
|---|---|---|---|
| `build-gate` | `npx tsc -b` | non-zero on a type error | record `gate_failed` |
| `build-gate` | `<pm> run lint` | non-zero on a lint finding | record `gate_failed` |
| `scan-secrets` | `git diff … HEAD` | 128, repo has no commits | scan the changed files |
| `check-licenses` | `git diff HEAD` | 128, repo has no commits | list new dependencies |

**`build-gate`'s type-error path had therefore never worked** on a modern PowerShell — the exact
condition it tests for was the condition that killed it.

The failure mode is what makes this dangerous: each script died *before* writing its log line, so
`Test-Path gate.log` returned false. That reads as **"the hook never fired"** when the truth is
**"the hook crashed"** — the same false-assurance pattern as `tool-guardian` logging `guard_passed`
with an empty `tool`. Fix:

```powershell
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false   # then test $LASTEXITCODE explicitly
```

Harmless on 5.1 and 7.0–7.2, where the variable is simply unused.

### That fix alone is NOT enough — the host runs Windows PowerShell 5.1

**The Copilot host launches hooks with `powershell.exe` (5.1), not `pwsh` 7.** In 5.1 the variable
above does not exist, so it is a no-op — and 5.1 has a *second*, independent failure mode:

> **A native command's STDERR becomes a TERMINATING ErrorRecord under `'Stop'`. No non-zero exit
> required, and `2>$null` does not prevent it.**

The redirect discards the stderr *text*; the error record is raised regardless. Verified 2026-07-27
by running the same script under both hosts:

| | `pwsh` 7.6.3 | `powershell.exe` 5.1 |
|---|---|---|
| `build-gate` lint step | exit 0, full report | **dead** — `NativeCommandError` |
| `scan-secrets` outside a repo | clean skip | **dead** at `git rev-parse --is-inside-work-tree` |

`pnpm` writes its banner (`$ eslint .`) to stderr on **every** run, so the lint step died every time.
And because `git rev-parse --is-inside-work-tree` writes `fatal: not a git repository` to stderr, the
"skip gracefully, this isn't a repo" path was **the one path guaranteed to crash**.

**Always test a hook script under `powershell.exe`, not just `pwsh`.** A green run under 7.x proves
nothing about the host.

The only reliable fix is to genuinely lower the preference around the call. Inline this helper and
route every native invocation through it — `lint-baseline.ps1` errors if a script shelling out under
`'Stop'` doesn't define it:

```powershell
function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string[]]$Arguments = @()
  )
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & $Command @Arguments 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { [string]$_ }
    }
    $code = $LASTEXITCODE
    return [PSCustomObject]@{ Output = @($out); ExitCode = $code }
  } catch {
    return [PSCustomObject]@{ Output = @($_.Exception.Message); ExitCode = 1 }
  } finally {
    $ErrorActionPreference = $prev
  }
}
```

Coercing ErrorRecords to strings is not cosmetic: left as records, they re-throw the moment anything
downstream touches them under `'Stop'`.

### `git init` with no commits is not the same as "no git repo"

`git rev-parse --is-inside-work-tree` **succeeds** in a freshly initialised repo — the repository
does exist. It just has no `HEAD`, so every `git diff HEAD` exits 128. That is the normal state of a
scaffolded project, and precisely when an unscanned credential is most likely sitting in a new file.
Guard it separately:

```powershell
$null = & git rev-parse --verify --quiet HEAD 2>&1
$HasCommits = ($LASTEXITCODE -eq 0)
```

With no commits, treat every tracked and untracked file as new (`git ls-files` plus
`git ls-files --others --exclude-standard`) rather than diffing against a revision that doesn't
exist. The bash variants fail *silently* here instead of crashing — `if git diff HEAD …` is simply
false, so the whole phase is skipped with no error and no findings.

### A detector must not scan itself

`scan-secrets` flagged 7 "secrets" on a clean project: its own detection regexes (a PGP header
pattern **is** a PGP header) and the worked examples in `hooks/*.README.md`. It now skips
`.github/hooks/` — deliberately *not* all of `.github/`, because a credential pasted into
`copilot-instructions.md` or a workflow file is a real finding. A guard that cries wolf gets ignored
wholesale, which is worse than one that misses a case.

## Verified separately

- `sessionStart` and `userPromptSubmitted` **do** fire in VS Code Copilot Chat.
- `sessionEnd` does **not** fire — **probe-verified**, including a full VS Code quit and the
  `SessionEnd` casing (see the event table above). `Stop` fires after every completed turn, which is
  why `build-gate`, `secrets-scanner` and `dependency-license-checker` are registered on it.
- This bullet once read *"UNVERIFIED, do not cite as established"*, written before the probe ran, and
  outlived the probe that settled it — leaving the file contradicting its own table. An
  under-evidenced claim in a repo doc gets read back as fact; so does a stale caveat.
- `preToolUse` **does** fire — the scripts run, they just cannot read what they were sent.
