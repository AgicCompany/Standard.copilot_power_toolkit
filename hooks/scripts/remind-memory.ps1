#Requires -Version 5.1
<#
.SYNOPSIS
  Memory Reminder Hook (PowerShell) - mirrors remind-memory.sh exactly; keep both in sync.
.DESCRIPTION
  Event: sessionStart. stdout IS PARSED for this event - it must be a single JSON object or nothing.

  This script used to call Write-Host, which lands on stdout and is not JSON. That did more than
  waste the reminder: on a parsed event, one malformed emitter appears to poison the whole batch, so
  the valid `additionalContext` from OTHER sessionStart hooks never reached the model either.
  Diagnosed 2026-08-01 - `dataverse-schema-drift` logged `emitted_drift_warning` while Copilot showed
  no sign of it, twice, until this script was found writing plain text alongside it.

  Rule for every sessionStart hook: emit one JSON object with `additionalContext`, or emit nothing.
  Never Write-Host, never Write-Output a bare string, never echo a status line.
.NOTES
  Env vars: SKIP_MEMORY_REMINDER (true to disable), MEMORY_FILE (default .github/docs/project-memory.md)
#>

$ErrorActionPreference = 'Stop'

if ($env:SKIP_MEMORY_REMINDER -eq 'true') {
  exit 0
}

$MemoryFile = if ($env:MEMORY_FILE) { $env:MEMORY_FILE } else { '.github/docs/project-memory.md' }

if (-not (Test-Path -LiteralPath $MemoryFile)) {
  # Silent by design. A brand-new project has no memory file and does not need to be told so on
  # every single session start - that is noise, and noise in injected context is not free.
  exit 0
}

$entryMatches = Select-String -LiteralPath $MemoryFile -Pattern '^\s*-\s+\d{4}-\d{2}-\d{2}:' -ErrorAction SilentlyContinue
$entryCount = if ($entryMatches) { @($entryMatches).Count } else { 0 }

if ($entryCount -eq 0) {
  exit 0
}

$plural = if ($entryCount -eq 1) { 'y' } else { 'ies' }
$msg = "Project memory: '$MemoryFile' has $entryCount recorded entr$plural. Read it before non-trivial work - it holds decisions and constraints for this project that are not derivable from the code."

# Payload MUST be nested under hookSpecificOutput with hookEventName. A flat
# { additionalContext } is accepted, errors nothing, and is silently discarded.
# Spec: https://code.visualstudio.com/docs/agent-customization/hooks
@{
  hookSpecificOutput = @{
    hookEventName     = 'SessionStart'
    additionalContext = $msg
  }
} | ConvertTo-Json -Compress -Depth 4
exit 0
