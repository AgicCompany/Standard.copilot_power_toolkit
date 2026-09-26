#Requires -Version 5.1
<#
.SYNOPSIS
  Tool Guardian Hook (PowerShell) - mirrors guard-tool.sh exactly; keep both in sync.
.NOTES
  Env vars: GUARD_MODE (warn|block, default block), SKIP_TOOL_GUARD (true to disable),
  TOOL_GUARD_LOG_DIR (default logs/copilot/tool-guardian), TOOL_GUARD_ALLOWLIST (comma-separated)
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


if ($env:SKIP_TOOL_GUARD -eq 'true') {
  exit 0
}

$Input_ = [Console]::In.ReadToEnd()

$Mode = if ($env:GUARD_MODE) { $env:GUARD_MODE } else { 'block' }
$LogDir = if ($env:TOOL_GUARD_LOG_DIR) { $env:TOOL_GUARD_LOG_DIR } else { 'logs/copilot/tool-guardian' }
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
# Best-effort: Write-HookLog creates this lazily too. Must not throw - a failed
# mkdir under ErrorActionPreference='Stop' would exit non-zero and, on preToolUse,
# block the tool call outright.
try { New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction Stop | Out-Null } catch { }
$LogFile = [System.IO.Path]::Combine($LogDir, 'guard.log')

# The documented payload field is "toolArgs" - a JSON STRING (not toolInput, not a nested object).
# That is the Copilot CLI reference shape; other hosts may differ, so nothing here assumes it worked.
$ToolName = ''
$ToolInput = ''

# A guard that cannot read its input must NEVER report success. Confirmed live: this script logged
# "guard_passed" 200+ times over several days with an empty toolName - it was inspecting nothing and
# reporting safety. False assurance is worse than a hook that plainly does not run, because the log
# looks healthy. If the payload is unusable, say so and stop; do not fall through to the threat scan.
if ([string]::IsNullOrWhiteSpace($Input_)) {
  Write-Host "[WARN] tool-guardian: no payload on stdin - nothing was inspected. This host may not"
  Write-Host "       pass hook input the way the scripts expect. See docs/reference/hook-payloads.md"
  [PSCustomObject]@{ timestamp = $Timestamp; event = 'guard_no_payload'; mode = $Mode; reason = 'empty_stdin' } |
    ConvertTo-Json -Compress | Write-HookLog -Path $LogFile
  exit 0
}

try {
  $parsed = $Input_ | ConvertFrom-Json -ErrorAction Stop
  # tool_name / tool_input  = VS Code Copilot Chat (tool_input is an OBJECT)
  # toolName  / toolArgs    = Copilot CLI docs      (toolArgs is a JSON STRING)
  # See docs/reference/hook-payloads.md - only the CLI shape was ever supported before.
  if ($parsed.PSObject.Properties.Name -contains 'tool_name' -and $parsed.tool_name) {
    $ToolName = [string]$parsed.tool_name
  }
  elseif ($parsed.toolName) { $ToolName = [string]$parsed.toolName }

  if ($parsed.PSObject.Properties.Name -contains 'tool_input' -and $parsed.tool_input) {
    $ToolInput = ($parsed.tool_input.PSObject.Properties | ForEach-Object { [string]$_.Value }) -join ' '
  }
  elseif ($parsed.toolArgs) {
    try {
      $argsObj = $parsed.toolArgs | ConvertFrom-Json -ErrorAction Stop
      # Flatten all values (command, path, description, whatever the tool provides) so pattern
      # matching catches a threat regardless of which field it's actually in.
      $ToolInput = ($argsObj.PSObject.Properties | ForEach-Object { [string]$_.Value }) -join ' '
    } catch {
      # toolArgs wasn't valid JSON (unexpected) - fall back to the raw string.
      $ToolInput = [string]$parsed.toolArgs
    }
  }
} catch {
  $m1 = [regex]::Match($Input_, '"toolName"\s*:\s*"([^"]*)"')
  if ($m1.Success) { $ToolName = $m1.Groups[1].Value }
  $m2 = [regex]::Match($Input_, '"toolArgs"\s*:\s*"((?:[^"\\]|\\.)*)"')
  if ($m2.Success) { $ToolInput = $m2.Groups[1].Value }
}

$Combined = "$ToolName $ToolInput"

$Allowlist = @()
if ($env:TOOL_GUARD_ALLOWLIST) {
  $Allowlist = $env:TOOL_GUARD_ALLOWLIST -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

function Test-Allowlisted {
  param([string]$Text)
  foreach ($p in $Allowlist) { if ($Text -like "*$p*") { return $true } }
  return $false
}

if ($Allowlist.Count -gt 0 -and (Test-Allowlisted -Text $Combined)) {
  [PSCustomObject]@{ timestamp = $Timestamp; event = 'guard_skipped'; reason = 'allowlisted'; tool = $ToolName } |
    ConvertTo-Json -Compress | Write-HookLog -Path $LogFile
  exit 0
}

# Each entry: category, severity, regex, suggestion
$Patterns = @(
  @{ Category = 'destructive_file_ops'; Severity = 'critical'; Regex = 'rm -rf /'; Suggestion = "Use targeted 'rm' on specific paths instead of root" }
  @{ Category = 'destructive_file_ops'; Severity = 'critical'; Regex = 'rm -rf ~'; Suggestion = "Use targeted 'rm' on specific paths instead of home directory" }
  @{ Category = 'destructive_file_ops'; Severity = 'critical'; Regex = 'rm -rf \.'; Suggestion = "Use targeted 'rm' on specific files instead of current directory" }
  @{ Category = 'destructive_file_ops'; Severity = 'critical'; Regex = 'rm -rf \.\.'; Suggestion = "Never remove parent directories recursively" }
  @{ Category = 'destructive_file_ops'; Severity = 'critical'; Regex = '(rm|del|unlink).*\.env'; Suggestion = "Use 'mv' to back up .env files before removing" }
  @{ Category = 'destructive_file_ops'; Severity = 'critical'; Regex = '(rm|del|unlink).*\.git[^i]'; Suggestion = "Never delete .git directory - use 'git' commands to manage repo state" }
  @{ Category = 'destructive_git_ops'; Severity = 'critical'; Regex = 'git push --force.*(main|master)'; Suggestion = "Use 'git push --force-with-lease' or push to a feature branch" }
  @{ Category = 'destructive_git_ops'; Severity = 'critical'; Regex = 'git push -f.*(main|master)'; Suggestion = "Use 'git push --force-with-lease' or push to a feature branch" }
  @{ Category = 'destructive_git_ops'; Severity = 'high'; Regex = 'git reset --hard'; Suggestion = "Use 'git stash' to preserve changes, or 'git reset --soft'" }
  @{ Category = 'destructive_git_ops'; Severity = 'high'; Regex = 'git clean -fd'; Suggestion = "Use 'git clean -n' (dry run) first to preview what will be deleted" }
  @{ Category = 'database_destruction'; Severity = 'critical'; Regex = 'DROP TABLE'; Suggestion = "Use 'ALTER TABLE' or create a migration with rollback support" }
  @{ Category = 'database_destruction'; Severity = 'critical'; Regex = 'DROP DATABASE'; Suggestion = "Create a backup first; consider revoking DROP privileges" }
  @{ Category = 'database_destruction'; Severity = 'critical'; Regex = 'TRUNCATE'; Suggestion = "Use 'DELETE FROM ... WHERE' with a condition for safer data removal" }
  @{ Category = 'database_destruction'; Severity = 'high'; Regex = 'DELETE FROM [a-zA-Z_]+ *;'; Suggestion = "Add a WHERE clause to 'DELETE FROM' to avoid deleting all rows" }
  @{ Category = 'permission_abuse'; Severity = 'high'; Regex = 'chmod 777'; Suggestion = "Use 'chmod 755' for directories or 'chmod 644' for files" }
  @{ Category = 'permission_abuse'; Severity = 'high'; Regex = 'chmod -R 777'; Suggestion = "Use specific permissions ('chmod -R 755') and limit scope" }
  @{ Category = 'network_exfiltration'; Severity = 'critical'; Regex = 'curl.*\|.*bash'; Suggestion = "Download the script first, review it, then execute" }
  @{ Category = 'network_exfiltration'; Severity = 'critical'; Regex = 'wget.*\|.*sh'; Suggestion = "Download the script first, review it, then execute" }
  @{ Category = 'network_exfiltration'; Severity = 'high'; Regex = 'curl.*--data.*@'; Suggestion = "Review what data is being sent before using 'curl --data @file'" }
  @{ Category = 'system_danger'; Severity = 'high'; Regex = 'sudo '; Suggestion = "Avoid 'sudo' - run commands with the least privilege needed" }
  @{ Category = 'system_danger'; Severity = 'high'; Regex = 'npm publish'; Suggestion = "Use 'npm publish --dry-run' first to verify package contents" }
)

$Threats = @()
foreach ($p in $Patterns) {
  $m = [regex]::Match($Combined, $p.Regex, 'IgnoreCase')
  if ($m.Success) {
    $Threats += [PSCustomObject]@{ category = $p.Category; severity = $p.Severity; match = $m.Value; suggestion = $p.Suggestion }
  }
}

# Parsed, but produced nothing usable - the payload shape does not match what this script expects.
# Log the truth rather than a clean pass.
if ([string]::IsNullOrWhiteSpace($ToolName) -and [string]::IsNullOrWhiteSpace($ToolInput)) {
  Write-Host "[WARN] tool-guardian: payload parsed but contained no toolName/toolArgs - nothing was"
  Write-Host "       inspected. Do not treat this as a pass. See docs/reference/hook-payloads.md"
  [PSCustomObject]@{ timestamp = $Timestamp; event = 'guard_unparsed_payload'; mode = $Mode; reason = 'no_toolname_or_toolargs' } |
    ConvertTo-Json -Compress | Write-HookLog -Path $LogFile
  exit 0
}

if ($Threats.Count -gt 0) {
  Write-Host ""
  Write-Host "[GUARD]  Tool Guardian: $($Threats.Count) threat(s) detected in '$ToolName' invocation"
  Write-Host ""
  " {0,-24} {1,-10} {2,-40} {3}" -f "CATEGORY", "SEVERITY", "MATCH", "SUGGESTION" | Write-Host
  " {0,-24} {1,-10} {2,-40} {3}" -f "--------", "--------", "-----", "----------" | Write-Host
  foreach ($t in $Threats) {
    $displayMatch = if ($t.match.Length -gt 38) { $t.match.Substring(0, 35) + '...' } else { $t.match }
    " {0,-24} {1,-10} {2,-40} {3}" -f $t.category, $t.severity, $displayMatch, $t.suggestion | Write-Host
  }
  Write-Host ""

  [PSCustomObject]@{
    timestamp = $Timestamp; event = 'threats_detected'; mode = $Mode; tool = $ToolName
    threat_count = $Threats.Count; threats = $Threats
  } | ConvertTo-Json -Compress -Depth 5 | Write-HookLog -Path $LogFile

  if ($Mode -eq 'block') {
    Write-Host "[BLOCKED] Operation blocked: resolve the threats above or adjust TOOL_GUARD_ALLOWLIST."
    Write-Host "  Set GUARD_MODE=warn to log without blocking."
    exit 1
  } else {
    Write-Host "[WARN]  Threats logged in warn mode. Set GUARD_MODE=block to prevent dangerous operations."
  }
} else {
  [PSCustomObject]@{ timestamp = $Timestamp; event = 'guard_passed'; mode = $Mode; tool = $ToolName } |
    ConvertTo-Json -Compress | Write-HookLog -Path $LogFile
}

exit 0
