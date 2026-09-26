#Requires -Version 5.1
# Log session end event (PowerShell) - mirrors log-session-end.sh exactly.

$ErrorActionPreference = 'Stop'

# Appends one JSON line to a log file. Uses .NET AppendAllText rather than Add-Content: the
# provider-backed cmdlet throws "Stream was not readable" when the Copilot host launches the script
# with its standard streams redirected, which is exactly how hooks are invoked. Observed live in a
# preToolUse hook.
#
# The try/catch is not decoration. These scripts run with $ErrorActionPreference = 'Stop', so a
# throw here terminates the script with a non-zero exit - and a non-zero exit from preToolUse BLOCKS
# THE TOOL CALL. A failure to write a log line must never deny Copilot an operation.
function Write-HookLog {
  param(
    [Parameter(ValueFromPipeline = $true)][string]$Json,
    [Parameter(Mandatory = $true)][string]$Path
  )
  process {
    try {
      $dir = Split-Path -Parent $Path
      if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        # Best-effort: Write-HookLog creates this lazily too. Must not throw - a failed
        # mkdir under ErrorActionPreference='Stop' would exit non-zero and, on preToolUse,
        # block the tool call outright.
        try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null } catch { }
      }
      [System.IO.File]::AppendAllText($Path, $Json + [Environment]::NewLine)
    } catch {
      # Deliberately swallowed - logging is never worth failing a hook over.
    }
  }
}


if ($env:SKIP_LOGGING -eq 'true') { exit 0 }

$raw = [Console]::In.ReadToEnd()

# This script is registered on BOTH 'sessionEnd' and 'Stop' (see session-logger.json), so a
# hardcoded label made every Stop firing read as 'sessionEnd' in the log. That is worse than an
# unlabelled entry: sessionEnd is probe-verified to NEVER fire in VS Code Copilot Chat, and the
# mislabelled log later convinced an audit that it did - contradicting a correct finding on the
# strength of the script's own bad bookkeeping. Same false-assurance class as tool-guardian logging
# guard_passed with an empty tool name. Take the event name from the payload the host actually sent.
$EventName = 'unknown'
if ($raw) {
  try {
    $payload = $raw | ConvertFrom-Json
    if ($payload.hook_event_name) { $EventName = [string]$payload.hook_event_name }
    elseif ($payload.hookEventName) { $EventName = [string]$payload.hookEventName }
  } catch { }
}

# Best-effort: Write-HookLog creates this lazily too. Must not throw - a failed

# mkdir under ErrorActionPreference='Stop' would exit non-zero and, on preToolUse,

# block the tool call outright.

try { New-Item -ItemType Directory -Path 'logs/copilot' -Force -ErrorAction Stop | Out-Null } catch { }
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

[PSCustomObject]@{ timestamp = $Timestamp; event = $EventName } |
  ConvertTo-Json -Compress | Write-HookLog -Path 'logs/copilot/session.log'

Write-Host "[LOG] $EventName logged"
exit 0
