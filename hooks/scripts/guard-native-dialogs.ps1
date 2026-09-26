#Requires -Version 5.1
<#
.SYNOPSIS
  Native Dialog Guard (PowerShell) - mirrors guard-native-dialogs.sh exactly; keep both in sync.
.DESCRIPTION
  Event: preToolUse. Denies writing `window.confirm` / `alert` / `prompt` into app source.

  WHY THIS IS A HOOK AND NOT AN INSTRUCTION. The rule exists in the instruction layer and was
  ignored three times on 2026-08-01/02, each time with different reasoning, each time after the
  previous wording was explicitly banned:

    1. `window.confirm` because shadcn was not installed
    2. "adding dependencies is out of scope"
    3. "avoid unnecessary setup overhead" -> hand-rolled a native <dialog>
    4. and finally, explicitly: "despite the baseline instructions naming them as the styling
       authority - I used a native window.confirm() ... instead of installing a whole UI library
       for one dialog"

  Step 4 is the reason this exists. That is not a rule failing to load; it is a rule being read,
  named, and overridden. `permissionDecision: deny` is the only mechanism in this baseline that has
  never been talked around, because a refusal cannot be weighed against the task - it has to be
  dealt with.

  In a Power Apps Code App the consequence is silent: the iframe sandbox lacks `allow-modals`, so
  `confirm()` returns false immediately, the destructive action never happens, nothing throws, and
  build, lint and tests all pass. The native <dialog> ELEMENT is unaffected by that flag and works
  fine - it is not blocked here, only bespoke reimplementation is discouraged, which stays an
  instruction-layer concern.
.NOTES
  Env vars: SKIP_DIALOG_GUARD (true to disable), DIALOG_GUARD_MODE (block|warn),
            DIALOG_GUARD_LOG_DIR
#>

$ErrorActionPreference = 'Stop'

# ValueFromPipeline + a process block are BOTH required. Callers pipe into this
# (`... | ConvertTo-Json -Compress | Write-HookLog -Path $LogFile`), and without the attribute $Json
# never binds - the function still runs and appends a bare newline, so the log file grows while
# containing nothing. Observed live: a 6-byte log of three empty lines after three real denials,
# which is indistinguishable from a hook that never ran. AppendAllText rather than Add-Content: the
# provider-backed cmdlet throws "Stream was not readable" when the host redirects standard streams,
# which is how hooks are invoked.
function Write-HookLog {
  param(
    [Parameter(ValueFromPipeline = $true)][string]$Json,
    [Parameter(Mandatory = $true)][string]$Path
  )
  process {
    try {
      if ([string]::IsNullOrWhiteSpace($Json)) { return }
      $dir = Split-Path -Parent $Path
      if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null } catch { }
      }
      [System.IO.File]::AppendAllText($Path, $Json + [Environment]::NewLine)
    } catch { }
  }
}

$LogFile = if ($env:DIALOG_GUARD_LOG_DIR) {
  [System.IO.Path]::Combine($env:DIALOG_GUARD_LOG_DIR, 'guard.log')
} else {
  [System.IO.Path]::Combine('logs', 'copilot', 'native-dialog-guard', 'guard.log')
}
$Timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

function Write-GuardLog {
  param([string]$EventName, [string]$FilePath, [string[]]$Calls, [string]$Mode)
  [PSCustomObject]@{
    timestamp = $Timestamp; event = $EventName; file = $FilePath
    calls = @($Calls); mode = $Mode
  } | ConvertTo-Json -Compress | Write-HookLog -Path $LogFile
}

if ($env:SKIP_DIALOG_GUARD -eq 'true') { exit 0 }

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

# Two payload dialects, same as guard-vite-env. Not gated on toolName: an unrecognised name would
# silently disable the guard, which is how a secret once reached .env.local unblocked.
$parsedArgs = $null
if ($payload.PSObject.Properties.Name -contains 'tool_input' -and $payload.tool_input) {
  $parsedArgs = $payload.tool_input
}
elseif ($payload.PSObject.Properties.Name -contains 'toolArgs' -and $payload.toolArgs) {
  try { $parsedArgs = $payload.toolArgs | ConvertFrom-Json -ErrorAction Stop } catch { $parsedArgs = $null }
}
if (-not $parsedArgs) { exit 0 }

$filePath = $null
foreach ($key in @('path', 'file_path', 'filePath', 'filepath', 'uri', 'targetFile', 'target_file', 'fileName')) {
  if ($parsedArgs.PSObject.Properties.Name -contains $key -and $parsedArgs.$key) { $filePath = [string]$parsedArgs.$key; break }
}
# A write tool is not the only way to create a file. Confirmed live 2026-08-03 against the sibling
# guard: blocked on the write tool, the model wrote the same content with `Set-Content -Path ...` in
# the terminal and reported it as "the pragmatic move". A shell command carries no path argument, so
# path-only filtering fails OPEN on the one route that defeats the guard. Extract the target path out
# of the command instead, so every check below still applies to it unchanged.
$command = $null
foreach ($key in @('command', 'cmd', 'commandLine', 'command_line', 'script', 'input', 'shellCommand')) {
  if ($parsedArgs.PSObject.Properties.Name -contains $key -and $parsedArgs.$key) { $command = [string]$parsedArgs.$key; break }
}

$isTerminalWrite = $false
if (-not $filePath -and $command) {
  # (Set|Add)-Content rather than the literal cmdlet name: lint-baseline flags that token in a hook
  # script and is right to - it just cannot tell a detection pattern from a call.
  if ($command -match '(?i)((Set|Add)-Content|Out-File|Tee-Object|New-Item|\btee\b|\bprintf\b|\becho\b|\bcat\b|>>?)') {
    $pathHit = [regex]::Match($command, '(?i)[^\s''";|&]+\.(tsx?|jsx?)\b')
    if ($pathHit.Success) {
      $filePath = $pathHit.Value
      $isTerminalWrite = $true
    }
  }
}

if (-not $filePath) { exit 0 }

# App source only. Tests legitimately stub these, and the baseline's own docs quote them while
# explaining the rule - blocking those would make the guard fire on the file that documents it.
$ext = [System.IO.Path]::GetExtension($filePath).ToLower()
if ($ext -notin @('.ts', '.tsx', '.js', '.jsx')) { exit 0 }
# (^|/) not just / - a relative path like 'node_modules/x/i.js' has no leading segment, and requiring
# one let it through. Caught by the discrimination probe, which is why that probe exists.
$norm = $filePath -replace '\\', '/'
if ($norm -match '(^|/)(node_modules|dist|build|\.github)/') { exit 0 }
if ($norm -match '\.(test|spec)\.[jt]sx?$') { exit 0 }

$content = $null
if ($isTerminalWrite) {
  # The whole command is the payload - the source being written is embedded in it as a quoted string.
  $content = $command
} else {
  foreach ($key in @('content', 'new_str', 'newText', 'text', 'newString', 'code', 'contents', 'newContent')) {
    if ($parsedArgs.PSObject.Properties.Name -contains $key -and $parsedArgs.$key) { $content = $parsedArgs.$key; break }
  }
}
if ([string]::IsNullOrWhiteSpace($content)) { exit 0 }

# `window.` prefix optional; `alert`/`prompt`/`confirm` must be a call, not an identifier. Requiring
# a word boundary before the name keeps `setPrompt(` and `this.confirm(` out of it.
$regex = '(?<![\w.$])(?:window\s*\.\s*)?(confirm|alert|prompt)\s*\('
$offenders = @()
foreach ($line in ($content -split "`r?`n")) {
  # Skip comment lines - documenting the ban is not violating it.
  if ($line -match '^\s*(//|\*|/\*)') { continue }
  $m = [regex]::Matches($line, $regex)
  foreach ($hit in $m) { $offenders += $hit.Groups[1].Value }
}
$offenders = $offenders | Sort-Object -Unique

if ($offenders.Count -eq 0) {
  Write-GuardLog -EventName 'guard_passed' -FilePath $filePath -Calls @() -Mode 'n/a'
  exit 0
}

$reason = @"
Refused: $($offenders -join ', ') cannot be used in a Power Apps Code App.

File: $filePath

Code Apps run inside an iframe whose sandbox lacks 'allow-modals'. There, confirm() does not show a dialog - it returns false IMMEDIATELY. So "confirm before deleting" becomes "silently never delete". Nothing throws. The build passes, lint passes, tests pass, and it works perfectly on localhost, which is where you will test it.

Fix: use the UI library this project is configured for. Read the 'ui' field in .github/.baseline-manifest.json - 'shadcn' means AlertDialog ('pnpm dlx shadcn@latest add alert-dialog'), 'fluent' means its Dialog. Installing it is part of finishing the work, not a separate task.

Do NOT hand-roll a dialog to avoid the install. A native <dialog> element does work here - it is unaffected by allow-modals - but a bespoke one matches nothing else in the app, ignores its theming and a11y conventions, and has to be maintained by hand forever, all to skip one install.

This guard inspects terminal commands as well as file writes, so writing the same code with Set-Content, echo, or a shell redirect is not a way around it, and doing so is not compliance.

If this genuinely is not a Code App, or this file never runs in the iframe, set SKIP_DIALOG_GUARD=true for the session. Do not work around this by renaming the call or splitting it across lines. If none of the above fits, STOP and tell the user what you were trying to write and why - let them decide.
"@

$mode = if ($env:DIALOG_GUARD_MODE) { $env:DIALOG_GUARD_MODE } else { 'block' }
Write-GuardLog -EventName $(if ($mode -eq 'warn') { 'guard_warned' } else { 'guard_denied' }) -FilePath $filePath -Calls $offenders -Mode $mode

if ($mode -eq 'warn') {
  @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $reason } } | ConvertTo-Json -Compress -Depth 4
  exit 0
}

# Emit both envelopes - the host parses whichever it recognises, as guard-vite-env does.
@{
  permissionDecision       = 'deny'
  permissionDecisionReason = $reason
  hookSpecificOutput       = @{
    hookEventName            = 'PreToolUse'
    permissionDecision       = 'deny'
    permissionDecisionReason = $reason
  }
} | ConvertTo-Json -Compress -Depth 5
exit 0
