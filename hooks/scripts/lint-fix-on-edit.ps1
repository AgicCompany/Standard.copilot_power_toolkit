#Requires -Version 5.1
<#
.SYNOPSIS
  Lint Fix On Edit Hook (PowerShell) - mirrors lint-fix-on-edit.sh exactly; keep both in sync.
.DESCRIPTION
  Event: postToolUse. stdout is IGNORED by the host for this event, so this hook fixes files rather
  than reporting; the agent's next read sees the corrected version.
.NOTES
  Env vars: SKIP_LINT_FIX (true to disable), LINT_FIX_PRETTIER (default true),
            LINT_FIX_EXTENSIONS (default ts,tsx,js,jsx,mjs,cjs)
#>

$ErrorActionPreference = 'SilentlyContinue'

if ($env:SKIP_LINT_FIX -eq 'true') { exit 0 }

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

# Deliberately NOT gated on toolName - names differ per host/version and an unrecognised one would
# silently disable this hook (same bug that stopped vite-env-guard firing). The file extension check
# below is the stable filter.

$resultType = if ($payload.PSObject.Properties.Name -contains 'toolResult' -and $payload.toolResult) {
  $payload.toolResult.resultType
} else { 'success' }
if ($resultType -and $resultType -ne 'success') { exit 0 }

# toolArgs is a JSON *string*, not a nested object - it needs a second parse. Getting this wrong is
# what made tool-guardian silently no-op for months.
# Two payload dialects - see docs/reference/hook-payloads.md.
#   VS Code Copilot Chat : tool_input is an OBJECT.  Copilot CLI: toolArgs is a JSON STRING.
$filePath = $null
$parsedArgs = $null
if ($payload.PSObject.Properties.Name -contains 'tool_input' -and $payload.tool_input) {
  $parsedArgs = $payload.tool_input
}
elseif ($payload.PSObject.Properties.Name -contains 'toolArgs' -and $payload.toolArgs) {
  try {
    # Not named $args - that is a PowerShell automatic variable.
    $parsedArgs = $payload.toolArgs | ConvertFrom-Json
  } catch { $parsedArgs = $null }
}
if ($parsedArgs) {
  foreach ($key in @('path', 'file_path', 'filePath', 'filepath', 'uri', 'targetFile', 'target_file', 'fileName')) {
    if ($parsedArgs.PSObject.Properties.Name -contains $key -and $parsedArgs.$key) {
      $filePath = [string]$parsedArgs.$key; break
    }
  }
}
if (-not $filePath -or -not (Test-Path -LiteralPath $filePath -PathType Leaf)) { exit 0 }

$normalised = $filePath.Replace('\', '/')
foreach ($skip in @('/node_modules/', '/dist/', '/build/', '/.next/', '/generated/')) {
  if ($normalised -like "*$skip*") { exit 0 }
}

$extensions = if ($env:LINT_FIX_EXTENSIONS) { $env:LINT_FIX_EXTENSIONS } else { 'ts,tsx,js,jsx,mjs,cjs' }
$allowed = $extensions.Split(',') | ForEach-Object { $_.Trim() }
$ext = [System.IO.Path]::GetExtension($filePath).TrimStart('.')
if ($allowed -notcontains $ext) { exit 0 }

if (-not (Test-Path -LiteralPath 'package.json')) { exit 0 }
if (-not (Get-Command npx -ErrorAction SilentlyContinue)) { exit 0 }

# Best-effort throughout: a formatting hook must never break the agent's workflow.
try { & npx --no-install eslint --fix $filePath *> $null } catch { }

$runPrettier = if ($env:LINT_FIX_PRETTIER) { $env:LINT_FIX_PRETTIER } else { 'true' }
if ($runPrettier -eq 'true') {
  try { & npx --no-install prettier --write $filePath *> $null } catch { }
}

exit 0
