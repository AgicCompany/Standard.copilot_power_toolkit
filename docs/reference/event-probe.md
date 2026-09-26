# Which Hook Events Actually Fire — Probe

Temporary diagnostic. Drop into a project, exercise Copilot, read the log, then **delete it**.

## Why this exists

`sessionEnd` appeared not to fire in VS Code Copilot Chat, which would leave `build-gate`,
`secrets-scanner` and `dependency-license-checker` permanently inert. That conclusion was drawn from
two observations (new chats, one window reload) and **not** properly tested before a manual
workaround was adopted — the same "work around it rather than diagnose it" pattern this baseline
tells agents to avoid.

Untested hypotheses:

1. `sessionEnd` fires only on a **full VS Code exit**, not a window reload.
2. The event has a **different name** in this dialect. The payload is Claude-Code-shaped
   (`hook_event_name: "PreToolUse"`, snake_case fields), so this host may expect `SessionEnd`,
   `Stop`, or something else — even though the camelCase `sessionStart`, `preToolUse` and
   `userPromptSubmitted` keys demonstrably work.
3. `agentStop` fires when a turn completes — which would be a **better** trigger than session end
   anyway, since the gate would run after each change rather than once at the very end.

### Results — recorded in `docs/reference/hook-payloads.md`

This probe has been run. Read the results before registering anything new:

1. **False.** `sessionEnd` never fires in VS Code Copilot Chat — not on a window reload and not on a
   full VS Code quit.
2. **Partly true.** **`Stop` (PascalCase) fires after every completed turn**, and is where the
   end-of-change hooks now run. `SessionEnd` does not fire either. Casing matters for tool events too:
   `PostToolUse` fires, camelCase `postToolUse` does not.
3. **Not re-probed.** `Stop` already covers the end-of-turn use case, so whether `agentStop` fires on
   this host has not been tested.

The probe below is kept for re-testing on a new host or Copilot version, not because these questions
are still open.

## The probe

`.github/hooks/event-probe.json` — registers every plausible event name, both casings:

```json
{
  "version": 1,
  "hooks": {
    "sessionEnd":      [{ "type": "command", "powershell": ".github/hooks/scripts/probe-event.ps1", "cwd": ".", "env": { "PROBE_EVENT": "sessionEnd" },      "timeoutSec": 10 }],
    "SessionEnd":      [{ "type": "command", "powershell": ".github/hooks/scripts/probe-event.ps1", "cwd": ".", "env": { "PROBE_EVENT": "SessionEnd" },      "timeoutSec": 10 }],
    "agentStop":       [{ "type": "command", "powershell": ".github/hooks/scripts/probe-event.ps1", "cwd": ".", "env": { "PROBE_EVENT": "agentStop" },       "timeoutSec": 10 }],
    "Stop":            [{ "type": "command", "powershell": ".github/hooks/scripts/probe-event.ps1", "cwd": ".", "env": { "PROBE_EVENT": "Stop" },            "timeoutSec": 10 }],
    "postToolUse":     [{ "type": "command", "powershell": ".github/hooks/scripts/probe-event.ps1", "cwd": ".", "env": { "PROBE_EVENT": "postToolUse" },     "timeoutSec": 10 }],
    "PostToolUse":     [{ "type": "command", "powershell": ".github/hooks/scripts/probe-event.ps1", "cwd": ".", "env": { "PROBE_EVENT": "PostToolUse" },     "timeoutSec": 10 }],
    "subagentStop":    [{ "type": "command", "powershell": ".github/hooks/scripts/probe-event.ps1", "cwd": ".", "env": { "PROBE_EVENT": "subagentStop" },    "timeoutSec": 10 }],
    "errorOccurred":   [{ "type": "command", "powershell": ".github/hooks/scripts/probe-event.ps1", "cwd": ".", "env": { "PROBE_EVENT": "errorOccurred" },   "timeoutSec": 10 }]
  }
}
```

`.github/hooks/scripts/probe-event.ps1`:

```powershell
$raw = [Console]::In.ReadToEnd()
try {
  if (-not (Test-Path -LiteralPath 'logs/copilot')) {
    New-Item -ItemType Directory -Path 'logs/copilot' -Force | Out-Null
  }
  $stamp = (Get-Date).ToUniversalTime().ToString('o')
  $name  = if ($env:PROBE_EVENT) { $env:PROBE_EVENT } else { 'unknown' }
  [System.IO.File]::AppendAllText('logs/copilot/event-probe.log',
    "$stamp  registered=$name  payloadLen=$($raw.Length)  raw=$raw" + [Environment]::NewLine)
} catch { }
exit 0
```

## Procedure

1. Create both files, **reload the window**.
2. Send a prompt that makes Copilot write a file, and let it finish. (`agentStop` / `Stop` should
   appear here if they exist.)
3. Start a new chat. Send another prompt.
4. **Fully quit VS Code** — not a reload — then reopen the project.
5. Read the log:

```powershell
Get-Content logs\copilot\event-probe.log | ForEach-Object { ($_ -split '  ')[0..2] -join '  ' }
```

## Interpreting

| Observed | Conclusion |
|---|---|
| `agentStop` or `Stop` entries | **Best outcome.** Move `build-gate` there — it runs per turn, better than session end. Needs debouncing so a long typecheck doesn't run on every message. |
| `SessionEnd` (PascalCase) but not `sessionEnd` | Event naming is dialect-specific. Register both casings in every hook. |
| `sessionEnd` only after a **full quit** | Not broken — just rarer than assumed. Keep it, and keep `pnpm gate` for mid-session use. |
| Nothing at all | The original conclusion holds, and the manual gate is the right answer — now actually established rather than assumed. |

**Delete both probe files afterwards.** The log records raw payloads.
