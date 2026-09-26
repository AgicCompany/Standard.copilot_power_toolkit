#Requires -Version 5.1
# Log session start event (PowerShell) - mirrors log-session-start.sh exactly.

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

$null = [Console]::In.ReadToEnd()

# Best-effort: Write-HookLog creates this lazily too. Must not throw - a failed

# mkdir under ErrorActionPreference='Stop' would exit non-zero and, on preToolUse,

# block the tool call outright.

try { New-Item -ItemType Directory -Path 'logs/copilot' -Force -ErrorAction Stop | Out-Null } catch { }
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$Cwd = (Get-Location).Path

[PSCustomObject]@{ timestamp = $Timestamp; event = 'sessionStart'; cwd = $Cwd } |
  ConvertTo-Json -Compress | Write-HookLog -Path 'logs/copilot/session.log'

# stdout is PARSED as JSON on sessionStart. A status line here silently suppresses additionalContext
# from EVERY other sessionStart hook. The real record goes to the log file above.
exit 0
