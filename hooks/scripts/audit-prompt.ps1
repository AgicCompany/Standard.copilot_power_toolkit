#Requires -Version 5.1
<#
.SYNOPSIS
  Governance Audit: scan user prompts for threat signals (PowerShell) - mirrors audit-prompt.sh
  exactly; keep both in sync.
.NOTES
  Env vars: GOVERNANCE_LEVEL (open|standard|strict|locked, default standard),
  BLOCK_ON_THREAT (true to exit non-zero), SKIP_GOVERNANCE_AUDIT (true to disable)
#>

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

$Input_ = [Console]::In.ReadToEnd()

# Best-effort: Write-HookLog creates this lazily too. Must not throw - a failed

# mkdir under ErrorActionPreference='Stop' would exit non-zero and, on preToolUse,

# block the tool call outright.

try { New-Item -ItemType Directory -Path 'logs/copilot/governance' -Force -ErrorAction Stop | Out-Null } catch { }

# logs/ is not in a project's .gitignore by default, and these files hold prompt fragments, file
# paths and commands. Make the folder ignore itself: it never edits the project's own .gitignore and
# works however the baseline was installed. Delete logs/copilot/.gitignore to commit logs on purpose.
try {
  $ignorePath = [System.IO.Path]::Combine((Get-Location).ProviderPath, 'logs', 'copilot', '.gitignore')
  if (-not (Test-Path -LiteralPath $ignorePath)) {
    $ignoreText = "# Created by the Copilot baseline hooks. These logs can hold prompt fragments,`n" +
      "# file paths and commands - they are not for version control. Delete this file only`n" +
      "# if you deliberately want to commit them.`n*`n"
    [System.IO.File]::WriteAllText($ignorePath, $ignoreText)
  }
} catch { }
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$Level = if ($env:GOVERNANCE_LEVEL) { $env:GOVERNANCE_LEVEL } else { 'standard' }
$Block = if ($env:BLOCK_ON_THREAT) { $env:BLOCK_ON_THREAT } else { 'false' }
$LogFile = 'logs/copilot/governance/audit.log'

$Prompt = ''
try {
  $parsed = $Input_ | ConvertFrom-Json -ErrorAction Stop
  if ($parsed.userMessage) { $Prompt = [string]$parsed.userMessage }
  elseif ($parsed.prompt) { $Prompt = [string]$parsed.prompt }
} catch { }
if (-not $Prompt) { $Prompt = $Input_ }

# category, description, severity (0.0-1.0)
$Patterns = @(
  @{ Regex = 'send\s+(all|every|entire)\s+\w+\s+to\s+'; Category = 'data_exfiltration'; Severity = 0.8; Description = 'Bulk data transfer' }
  @{ Regex = 'export\s+.*\s+to\s+(external|outside|third[_-]?party)'; Category = 'data_exfiltration'; Severity = 0.9; Description = 'External export' }
  @{ Regex = 'curl\s+.*\s+-d\s+'; Category = 'data_exfiltration'; Severity = 0.7; Description = 'HTTP POST with data' }
  @{ Regex = 'upload\s+.*\s+(credentials|secrets|keys)'; Category = 'data_exfiltration'; Severity = 0.95; Description = 'Credential upload' }
  @{ Regex = '(sudo|as\s+root|admin\s+access|runas\s+/user)'; Category = 'privilege_escalation'; Severity = 0.8; Description = 'Elevated privileges' }
  @{ Regex = 'chmod\s+777'; Category = 'privilege_escalation'; Severity = 0.9; Description = 'World-writable permissions' }
  @{ Regex = 'add\s+.*\s+(sudoers|administrators)'; Category = 'privilege_escalation'; Severity = 0.95; Description = 'Adding admin access' }
  @{ Regex = '(rm\s+-rf\s+/|del\s+/[sq]|format\s+c:)'; Category = 'system_destruction'; Severity = 0.95; Description = 'Destructive command' }
  @{ Regex = '(drop\s+database|truncate\s+table|delete\s+from\s+\w+\s*(;|\s*$))'; Category = 'system_destruction'; Severity = 0.9; Description = 'Database destruction' }
  @{ Regex = 'wipe\s+(all|entire|every)'; Category = 'system_destruction'; Severity = 0.9; Description = 'Mass deletion' }
  @{ Regex = 'ignore\s+(previous|above|all)\s+(instructions?|rules?|prompts?)'; Category = 'prompt_injection'; Severity = 0.9; Description = 'Instruction override' }
  @{ Regex = 'you\s+are\s+now\s+(a|an)\s+(assistant|ai|bot|system|expert|language\s+model)\b'; Category = 'prompt_injection'; Severity = 0.7; Description = 'Role reassignment' }
  @{ Regex = '(^|\n)\s*system\s*:\s*you\s+are'; Category = 'prompt_injection'; Severity = 0.6; Description = 'System prompt injection' }
  @{ Regex = "(api[_-]?key|secret[_-]?key|password|token)\s*[:=]\s*['\`"]?\w{8,}"; Category = 'credential_exposure'; Severity = 0.9; Description = 'Possible hardcoded credential' }
  @{ Regex = '(aws_access_key|AKIA[0-9A-Z]{16})'; Category = 'credential_exposure'; Severity = 0.95; Description = 'AWS key exposure' }
)

# Replaces every credential-shaped substring with its first and last 4 characters, or [REDACTED]
# when there are too few to hide anything - the same rule scan-secrets uses. Applied to the evidence
# of EVERY category, not just credential_exposure: a greedy pattern such as "export .* to external"
# captures whatever lies between its anchors, and once captured a password was logged whole.
# The patterns come from the table above, so detection and redaction cannot drift apart.
$CredentialRegexes = @($Patterns | Where-Object { $_.Category -eq 'credential_exposure' } | ForEach-Object { $_.Regex })
function Hide-Credentials {
  param([string]$Text)
  foreach ($rx in $CredentialRegexes) {
    $Text = [regex]::Replace($Text, $rx, {
      param($match)
      $v = $match.Value
      if ($v.Length -le 12) { '[REDACTED]' } else { "$($v.Substring(0,4))...$($v.Substring($v.Length-4))" }
    }, 'IgnoreCase')
  }
  return $Text
}

$ThreatsFound = @()
foreach ($p in $Patterns) {
  $m = [regex]::Match($Prompt, $p.Regex, 'IgnoreCase')
  if ($m.Success) {
    $evidence = Hide-Credentials $m.Value
    $ThreatsFound += [PSCustomObject]@{ category = $p.Category; severity = $p.Severity; description = $p.Description; evidence = $evidence }
  }
}

if ($ThreatsFound.Count -gt 0) {
  $maxSeverity = ($ThreatsFound | Measure-Object -Property severity -Maximum).Maximum

  [PSCustomObject]@{
    timestamp = $Timestamp; event = 'threat_detected'; governance_level = $Level
    threat_count = $ThreatsFound.Count; max_severity = $maxSeverity; threats = $ThreatsFound
  } | ConvertTo-Json -Compress -Depth 5 | Write-HookLog -Path $LogFile

  Write-Host "[WARN] Governance: $($ThreatsFound.Count) threat signal(s) detected (max severity: $maxSeverity)"
  foreach ($t in $ThreatsFound) {
    Write-Host " [CRITICAL] [$($t.category)] $($t.description) (severity: $($t.severity))"
  }

  if ($Block -eq 'true' -or $Level -eq 'strict' -or $Level -eq 'locked') {
    Write-Host "[BLOCKED] Prompt blocked by governance policy (level: $Level)"
    exit 1
  }
} else {
  [PSCustomObject]@{ timestamp = $Timestamp; event = 'prompt_scanned'; governance_level = $Level; status = 'clean' } |
    ConvertTo-Json -Compress | Write-HookLog -Path $LogFile
}

exit 0
