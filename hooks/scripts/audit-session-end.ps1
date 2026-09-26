#Requires -Version 5.1
# Governance Audit: log session end with summary statistics (PowerShell) - mirrors
# audit-session-end.sh exactly.

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


if ($env:SKIP_GOVERNANCE_AUDIT -eq 'true') { exit 0 }

$null = [Console]::In.ReadToEnd()

# Best-effort: Write-HookLog creates this lazily too. Must not throw - a failed

# mkdir under ErrorActionPreference='Stop' would exit non-zero and, on preToolUse,

# block the tool call outright.

try { New-Item -ItemType Directory -Path 'logs/copilot/governance' -Force -ErrorAction Stop | Out-Null } catch { }
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$LogFile = 'logs/copilot/governance/audit.log'

$Total = 0
$Threats = 0

if (Test-Path -LiteralPath $LogFile) {
  $lines = @(Get-Content -LiteralPath $LogFile -ErrorAction SilentlyContinue)
  $entries = @()
  foreach ($line in $lines) {
    try { $entries += ($line | ConvertFrom-Json) } catch { }
  }

  $sessionStarts = $entries | Where-Object { $_.event -eq 'session_start' }
  $sessionStart = if ($sessionStarts) { ($sessionStarts | Select-Object -Last 1).timestamp } else { $null }

  if ($sessionStart) {
    $inSession = $entries | Where-Object { $_.timestamp -ge $sessionStart }
    $Total = @($inSession).Count
    $Threats = @($inSession | Where-Object { $_.event -eq 'threat_detected' }).Count
  } else {
    $Total = $lines.Count
    $Threats = @($entries | Where-Object { $_.event -eq 'threat_detected' }).Count
  }
}

[PSCustomObject]@{ timestamp = $Timestamp; event = 'session_end'; total_events = $Total; threats_detected = $Threats } |
  ConvertTo-Json -Compress | Write-HookLog -Path $LogFile

if ($Threats -gt 0) {
  Write-Host "[WARN] Session ended: $Threats threat(s) detected in $Total events"
} else {
  Write-Host "[OK] Session ended: $Total events, no threats"
}

exit 0
