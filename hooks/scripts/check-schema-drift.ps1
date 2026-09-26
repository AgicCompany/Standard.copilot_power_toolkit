#Requires -Version 5.1
<#
.SYNOPSIS
  Dataverse Schema Drift Hook (PowerShell) - mirrors check-schema-drift.sh exactly; keep both in sync.
.DESCRIPTION
  Event: sessionStart. stdout IS parsed for this event - `additionalContext` is injected into the
  session, which is how the warning reaches Copilot.
.NOTES
  Env vars: SKIP_SCHEMA_DRIFT (true to disable), POWER_CONFIG (default power.config.json),
            GENERATED_DIR (default src/generated)
#>

$ErrorActionPreference = 'Stop'

# Every exit path logs. Without this the hook is undiagnosable: it emits nothing on the common path
# by design, so "no warning appeared" could mean it never ran, ran and found no drift, or ran and
# had its output dropped. That ambiguity cost a full acceptance-test step (D5) before this existed.
#
# stdout is PARSED on sessionStart, so logging must never touch it. File only.
# AppendAllText rather than Add-Content: the provider-backed cmdlet throws "Stream was not readable"
# when the host launches the script with redirected streams, which is how hooks are invoked.
function Write-DriftLog {
  param([string]$Decision, [string]$Detail = '')
  try {
    $path = if ($env:SCHEMA_DRIFT_LOG_DIR) {
      [System.IO.Path]::Combine($env:SCHEMA_DRIFT_LOG_DIR, 'drift.log')
    } else {
      [System.IO.Path]::Combine('logs', 'copilot', 'dataverse-schema-drift', 'drift.log')
    }
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
      try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null } catch { }
    }
    $line = @{
      timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
      event     = 'sessionStart'
      decision  = $Decision
      detail    = $Detail
    } | ConvertTo-Json -Compress
    [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine)
  } catch { }
}

if ($env:SKIP_SCHEMA_DRIFT -eq 'true') { Write-DriftLog 'skipped' 'SKIP_SCHEMA_DRIFT=true'; exit 0 }

$configPath = if ($env:POWER_CONFIG) { $env:POWER_CONFIG } else { 'power.config.json' }
$generatedDir = if ($env:GENERATED_DIR) { $env:GENERATED_DIR } else { 'src/generated' }

# Not a Power Apps Code App, or codegen has never run - nothing to compare.
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
  Write-DriftLog 'not_a_code_app' "no $configPath"
  exit 0
}
if (-not (Test-Path -LiteralPath $generatedDir -PathType Container)) {
  $msg = "Dataverse: '$configPath' exists but '$generatedDir' does not. If this app uses Dataverse data sources, the typed services have not been generated yet - run 'pa app add data-source' before writing data access code."
  @{
    hookSpecificOutput = @{
      hookEventName     = 'SessionStart'
      additionalContext = $msg
    }
  } | ConvertTo-Json -Compress -Depth 4
  Write-DriftLog 'emitted_no_generated_dir' $generatedDir
  exit 0
}

$generatedFiles = @(Get-ChildItem -LiteralPath $generatedDir -Recurse -File -ErrorAction SilentlyContinue)
if ($generatedFiles.Count -eq 0) { Write-DriftLog 'no_generated_files' $generatedDir; exit 0 }

$configTime = (Get-Item -LiteralPath $configPath).LastWriteTimeUtc
$newestGenerated = ($generatedFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
$generatedTime = $newestGenerated.LastWriteTimeUtc

if ($configTime -le $generatedTime) {
  Write-DriftLog 'no_drift' "config $($configTime.ToString('u')) <= generated $($generatedTime.ToString('u'))"
  exit 0
}

$span = $configTime - $generatedTime
$drift = if ($span.TotalHours -lt 1) { 'less than an hour' }
         elseif ($span.TotalHours -lt 48) { "$([math]::Round($span.TotalHours)) hour(s)" }
         else { "$([math]::Round($span.TotalDays)) day(s)" }
$msg = @"
ACT ON THIS BEFORE WRITING DATA ACCESS CODE. This is a gate, not background information.

Dataverse schema drift: '$configPath' was modified $drift AFTER the newest file in '$generatedDir', so the generated services may no longer match the configured data sources.

STOP - ACT ON THIS BEFORE YOUR FIRST EDIT. This is a gate, not background information.

If the task involves reading or writing Dataverse - a query hook, a service call, a component showing records - raise this in your FIRST reply and END THE TURN. **Raising it and then proceeding in the same turn is not compliance**, and neither is "I'll start looking at the files while you decide". Code written against stale types looks correct, compiles, and passes tests, which is exactly why the user has to answer before it exists.

If you judge that the specific operation cannot be affected - a delete that takes only a record id, say - state that reasoning and still wait. Whether the risk is acceptable is the user's call, not yours: you cannot see what changed in Dataverse, and that is the whole point of this warning.

Why nothing else will catch it: generated types agree with themselves, so TypeScript compiles and lint passes; tests mock at the service boundary, so they pass too. It surfaces at runtime as a Dataverse error about a missing column or an unset required field, often partially - some records save, some do not.

Offer to regenerate with 'pa app refresh data-source --name <name>'. Never hand-edit '$generatedDir' - it is overwritten wholesale.

If the task does not touch Dataverse, or the user says '$configPath' was changed for unrelated reasons, proceed without raising it again.
"@

# The payload MUST be nested under hookSpecificOutput, with hookEventName alongside it. A flat
# { "additionalContext": "..." } is accepted, produces no error, and is silently discarded - which is
# how this hook appeared to work for months while never reaching the model once.
# Spec: https://code.visualstudio.com/docs/agent-customization/hooks
@{
  hookSpecificOutput = @{
    hookEventName     = 'SessionStart'
    additionalContext = $msg
  }
} | ConvertTo-Json -Compress -Depth 4
Write-DriftLog 'emitted_drift_warning' $drift
exit 0
