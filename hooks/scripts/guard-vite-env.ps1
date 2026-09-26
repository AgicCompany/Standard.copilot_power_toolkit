#Requires -Version 5.1
<#
.SYNOPSIS
  Vite Env Guard Hook (PowerShell) - mirrors guard-vite-env.sh exactly; keep both in sync.
.DESCRIPTION
  Event: preToolUse. stdout IS parsed for this event, so denial reaches the model with a reason.
.NOTES
  Env vars: SKIP_VITE_ENV_GUARD (true to disable), VITE_ENV_GUARD_MODE (block|warn),
            VITE_ENV_GUARD_PATTERNS (comma-separated extra name fragments)
#>

$ErrorActionPreference = 'Stop'

# Appends one JSON line to a log file. Uses .NET AppendAllText rather than Add-Content: the
# provider-backed cmdlet throws "Stream was not readable" when the Copilot host launches the script
# with its standard streams redirected, which is exactly how hooks are invoked.
#
# The try/catch is not decoration. This script runs with $ErrorActionPreference = 'Stop' on a
# preToolUse event, where a non-zero exit BLOCKS THE TOOL CALL. A failed log write must never deny
# Copilot an operation - failing open on logging is correct here even though the guard itself
# fails closed.
function Write-HookLog {
  param(
    [Parameter(ValueFromPipeline = $true)][string]$Json,
    [Parameter(Mandatory = $true)][string]$Path
  )
  process {
    try {
      $dir = Split-Path -Parent $Path
      if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null } catch { }
      }
      [System.IO.File]::AppendAllText($Path, $Json + [Environment]::NewLine)
    } catch { }
  }
}

$LogFile = if ($env:VITE_ENV_GUARD_LOG_DIR) {
  [System.IO.Path]::Combine($env:VITE_ENV_GUARD_LOG_DIR, 'guard.log')
} else {
  [System.IO.Path]::Combine('logs', 'copilot', 'vite-env-guard', 'guard.log')
}
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# NEVER log a value - only variable names and decisions. This file records what was blocked, and a
# log of blocked credentials that contains the credentials defeats the purpose.
# $Event is a PowerShell AUTOMATIC variable (eventing subsystem) - assigning to it in a param block
# is a real hazard, not a style nit. Same class of bug as $Profile and $args, both of which broke
# tools/apply-baseline.ps1 previously.
function Write-GuardLog {
  param([string]$EventName, [string]$FilePath, [string[]]$Names, [string]$Mode)
  [PSCustomObject]@{
    timestamp = $Timestamp; event = $EventName; file = $FilePath
    variables = @($Names); mode = $Mode
  } | ConvertTo-Json -Compress | Write-HookLog -Path $LogFile
}

if ($env:SKIP_VITE_ENV_GUARD -eq 'true') { exit 0 }

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

# Deliberately NOT gated on toolName. Tool names differ between hosts and versions, and an
# unrecognised name would silently disable this guard - confirmed live: a matcher of 'edit'/'create'
# never fired in VS Code Chat and a secret was written to .env.local unblocked. The target path is
# the stable signal, so any tool writing a .env file is inspected.

# Two payload dialects exist in the wild. Support both - do not assume either.
#   VS Code Copilot Chat : { "tool_name": "create_file", "tool_input": { "filePath": ..., "content": ... } }
#                          snake_case, and tool_input is a real OBJECT (no second parse).
#   Copilot CLI docs     : { "toolName": "edit", "toolArgs": "{\"path\":...}" }
#                          camelCase, and toolArgs is a JSON STRING (needs a second parse).
# Confirmed live by capturing a real payload - see docs/reference/hook-payloads.md. Everything here
# was originally written against the CLI shape only, so no field was ever found in VS Code Chat.
$parsedArgs = $null
if ($payload.PSObject.Properties.Name -contains 'tool_input' -and $payload.tool_input) {
  $parsedArgs = $payload.tool_input
}
elseif ($payload.PSObject.Properties.Name -contains 'toolArgs' -and $payload.toolArgs) {
  try { $parsedArgs = $payload.toolArgs | ConvertFrom-Json -ErrorAction Stop } catch { $parsedArgs = $null }
}
if (-not $parsedArgs) { exit 0 }

# Hosts name this argument differently; check every spelling seen in the wild rather than assuming.
$filePath = $null
foreach ($key in @('path', 'file_path', 'filePath', 'filepath', 'uri', 'targetFile', 'target_file', 'fileName')) {
  if ($parsedArgs.PSObject.Properties.Name -contains $key -and $parsedArgs.$key) { $filePath = [string]$parsedArgs.$key; break }
}
# A write tool is not the only way to create a file. Confirmed live 2026-08-03: blocked on the write
# tool, a model wrote the same secret with `Set-Content -Path .env.local` in the terminal and reported
# it as "the pragmatic move". A shell command carries no path argument, so path-only filtering fails
# OPEN on the one route that bypasses the guard entirely. Inspect the command string too.
$command = $null
foreach ($key in @('command', 'cmd', 'commandLine', 'command_line', 'script', 'input', 'shellCommand')) {
  if ($parsedArgs.PSObject.Properties.Name -contains $key -and $parsedArgs.$key) { $command = [string]$parsedArgs.$key; break }
}

$isTerminalWrite = $false
if (-not $filePath -and $command) {
  $mentionsEnvFile = $command -match '(?i)(^|[\s''"=/\\])\.env(\.[A-Za-z0-9_.-]+)?([\s''";|&]|$)'
  # Written as (Set|Add)-Content rather than spelling both out: lint-baseline flags the literal
  # cmdlet name in a hook script, and it is right to - it just cannot tell a detection pattern from
  # a call. Keep it this way so the rule stays strict for everyone else.
  $looksLikeWrite = $command -match '(?i)((Set|Add)-Content|Out-File|Tee-Object|New-Item|\btee\b|\bprintf\b|\becho\b|\bcat\b|>>?)'
  if ($mentionsEnvFile -and $looksLikeWrite) {
    $isTerminalWrite = $true
    $filePath = '<terminal command>'
  }
}

if (-not $filePath) { exit 0 }

if (-not $isTerminalWrite) {
  # Only .env-family files. A secret in a .ts file is secrets-scanner's job.
  $base = [System.IO.Path]::GetFileName($filePath)
  if (-not ($base -eq '.env' -or $base -like '.env.*' -or $base -like '*.env')) { exit 0 }
}

$content = $null
if ($isTerminalWrite) {
  $content = $command
} else {
  foreach ($key in @('content', 'new_str', 'newText', 'text', 'newString', 'code', 'contents', 'newContent')) {
    if ($parsedArgs.PSObject.Properties.Name -contains $key -and $parsedArgs.$key) { $content = $parsedArgs.$key; break }
  }
}
if ([string]::IsNullOrWhiteSpace($content)) { exit 0 }

$patterns = 'SECRET|KEY|TOKEN|PASSWORD|PWD|CREDENTIAL|PRIVATE|CONNECTION_STRING|CLIENT_SECRET|API_KEY|SAS|CERT'
if ($env:VITE_ENV_GUARD_PATTERNS) {
  $extra = ($env:VITE_ENV_GUARD_PATTERNS -replace '\s', '') -replace ',', '|'
  if ($extra) { $patterns = "$patterns|$extra" }
}

# Explicit per-name exceptions, e.g. VITE_ENV_GUARD_ALLOW="VITE_APP_INSIGHTS_KEY,VITE_STRIPE_PUBLISHABLE_KEY".
# Some values are genuinely public despite a matching name - an Application Insights instrumentation
# key and a Stripe publishable key are both designed to ship to the browser. The fix for a false
# positive is a named, auditable exception, NOT renaming the variable until the check stops firing.
# Observed live: told the guard had blocked VITE_APP_INSIGHTS_KEY, a model suggested renaming to
# VITE_APPINSIGHTS_ID to get past it. That hollows the guard out one variable at a time.
#
# Two sources, because the env var alone is not usable by an agent. Confirmed live 2026-08-03: a model
# correctly added the name to the `env` block of vite-env-guard.json, the change needed a host reload
# to take effect, the model read the non-effect as "this path is broken", and bypassed the guard via
# the terminal. Worse, vite-env-guard.json is baseline-owned - the next `apply-baseline -Force` would
# have erased the exception anyway. An escape hatch that is invisible until reload and deleted on the
# next sync is not an escape hatch.
#
# `.github/vite-env-guard.allow` is project-owned (seeded once by apply-baseline, never overwritten)
# and is re-read on EVERY invocation, so an addition takes effect on the next tool call with no reload.
$allowList = @()
if ($env:VITE_ENV_GUARD_ALLOW) {
  $allowList = ($env:VITE_ENV_GUARD_ALLOW -split ',') | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ }
}

$allowFile = if ($env:VITE_ENV_GUARD_ALLOW_FILE) { $env:VITE_ENV_GUARD_ALLOW_FILE } else { '.github/vite-env-guard.allow' }
if (Test-Path -LiteralPath $allowFile) {
  try {
    $allowList += (Get-Content -LiteralPath $allowFile -ErrorAction Stop) |
      ForEach-Object { ($_ -replace '#.*', '').Trim().ToUpper() } |
      Where-Object { $_ }
  } catch { }
}
$allowList = $allowList | Sort-Object -Unique

# Names that cannot denote a credential no matter which pattern word they contain. VITE_TOKEN_ENDPOINT
# and VITE_API_KEY_HEADER_NAME are a URL and a header name; blocking them trains people to ignore the
# guard, and AGENTS.md is explicit that a guard which cries wolf gets disabled wholesale.
$structuralSuffixes = '(_URL|_ENDPOINT|_ID|_NAME|_HEADER|_PREFIX|_ISSUER|_AUTHORITY|_TENANT|_REGION|_VERSION)$'

# The public-variable prefix is CONFIGURABLE, not hardcoded. Vite exposes VITE_; Next.js exposes
# NEXT_PUBLIC_. A guard that only knows one of them logs a clean pass while a secret ships in the
# bundle of the other - the exact fail-open this baseline exists to eliminate. Set
# PUBLIC_ENV_PREFIXES (comma separated) to serve another stack from this same guard rather than
# forking it; forked mirrors drift, and we have already paid for that lesson twice.
$prefixList = if ($env:PUBLIC_ENV_PREFIXES) { $env:PUBLIC_ENV_PREFIXES } else { 'VITE_' }
$prefixAlt = (($prefixList -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } |
  ForEach-Object { [regex]::Escape($_) }) -join '|'
if (-not $prefixAlt) { $prefixAlt = 'VITE_' }

$regex = "^\s*(export\s+)?($prefixAlt)[A-Z0-9_]*($patterns)[A-Z0-9_]*\s*=\s*(\S.*)$"

# In a shell command the assignment sits mid-string inside quotes, so the line anchors above never
# match. Pull out each VITE_NAME=VALUE pair wherever it appears instead.
$looseRegex = "($prefixAlt)[A-Z0-9_]*($patterns)[A-Z0-9_]*\s*=\s*([^\s'`";|&]+)"

$candidates = @()
if ($isTerminalWrite) {
  foreach ($match in [regex]::Matches($content, $looseRegex)) {
    $candidates += @{
      Name  = ($match.Value -replace '\s*=.*', '').Trim()
      Value = ($match.Value -replace '^[^=]*=\s*', '').Trim().Trim('"').Trim("'")
    }
  }
} else {
  foreach ($line in ($content -split "`r?`n")) {
    if ($line -notmatch $regex) { continue }
    $candidates += @{
      Name  = (($line -replace '^\s*(export\s+)?', '') -replace '\s*=.*', '').Trim()
      Value = ($line -replace '^[^=]*=\s*', '').Trim().Trim('"').Trim("'")
    }
  }
}

$offenders = @()
$allowed = @()
foreach ($candidate in $candidates) {
  $name = $candidate.Name
  $value = $candidate.Value

  # A URL is not a credential, whatever the variable is called.
  if ($value -match '^https?://') { $allowed += $name; continue }
  if ($name.ToUpper() -match $structuralSuffixes) { $allowed += $name; continue }
  if ($allowList -contains $name.ToUpper()) { $allowed += $name; continue }

  $offenders += "$name=<redacted>"
}
$offenders = $offenders | Sort-Object -Unique
$allowed = $allowed | Sort-Object -Unique

if ($allowed.Count -gt 0) { Write-GuardLog -EventName 'guard_allowed_exception' -FilePath $filePath -Names $allowed -Mode 'n/a' }

if ($offenders.Count -eq 0) {
  Write-GuardLog -EventName 'guard_passed' -FilePath $filePath -Names @() -Mode 'n/a'
  exit 0
}

$reason = @"
Refused: this variable's prefix compiles its value into the client bundle, where anyone who loads the app can read it.

Offending assignments in ${filePath}:
$($offenders -join "`n")

Any variable with a public prefix (VITE_ in Vite, NEXT_PUBLIC_ in Next) ships to the browser - this is not configuration, it is a published credential.

Fix: drop the public prefix so the value stays server-side, or move the secret to a Power Platform connection / server-side proxy and have the client call that instead. See instructions/vite-env-and-secrets.instructions.md.

If this value is genuinely public (an Application Insights connection string, a Stripe publishable key), it is allowed - record the exception instead of working around the block:

  Append the EXACT variable name, one per line, to .github/vite-env-guard.allow

That file is read on every invocation, so it takes effect on your very next tool call with no reload. Then retry the original write. Do NOT edit the env block in .github/hooks/vite-env-guard.json - that needs a host reload to apply and is overwritten by the next baseline sync.

This guard inspects terminal commands as well as file writes, so writing the same value with Set-Content, echo, or a shell redirect is not a way around it, and doing so is not compliance. If the allow file does not resolve the block, STOP and tell the user what you were trying to write and why you believe the value is public. Let them decide - do not rename the variable until the check stops firing, which removes the guard for that value permanently and leaves no record of the decision.
"@

$mode = if ($env:VITE_ENV_GUARD_MODE) { $env:VITE_ENV_GUARD_MODE } else { 'block' }
$offenderNames = @($offenders | ForEach-Object { ($_ -replace '=<redacted>$', '') })
Write-GuardLog -EventName $(if ($mode -eq 'warn') { 'guard_warned' } else { 'guard_denied' }) -FilePath $filePath -Names $offenderNames -Mode $mode

if ($mode -eq 'warn') {
  @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $reason } } | ConvertTo-Json -Compress -Depth 4
  exit 0
}

# Emit both known envelopes - the host parses whichever it recognises, and an unrecognised
# extra key is ignored. Which dialect this host expects for the RESPONSE is still unverified.
@{
  permissionDecision       = 'deny'
  permissionDecisionReason = $reason
  hookSpecificOutput       = @{
    hookEventName            = 'PreToolUse'
    permissionDecision       = 'deny'
    permissionDecisionReason = $reason
  }
} | ConvertTo-Json -Compress -Depth 4
exit 0
