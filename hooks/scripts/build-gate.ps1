#Requires -Version 5.1
<#
.SYNOPSIS
  Build Gate Hook (PowerShell) - runs TypeScript type-checking (and lint, if configured) at session
  end so a session doesn't quietly end in a broken state. Mirrors build-gate.sh exactly; keep both in
  sync when changing either.

.NOTES
  Env vars: GATE_MODE (warn|block, default warn), SKIP_BUILD_GATE (true to disable),
  GATE_LOG_DIR (default logs/copilot/build-gate), GATE_RUN_LINT (false to skip lint),
  GATE_CONVENTIONS (off|warn|block, default warn) - mechanical convention checks; 'block' fails the
  gate on its own regardless of GATE_MODE.
#>

$ErrorActionPreference = 'Stop'

# PowerShell 7.3+ turns a native command's non-zero EXIT CODE into a terminating error whenever
# $ErrorActionPreference is 'Stop'. That is fatal here, because a non-zero exit is the normal signal
# this script exists to read: 'tsc -b' exits non-zero on a type error, 'eslint' on a lint finding,
# 'git diff HEAD' on a repo with no commits. Redirecting with 2>$null suppresses the stderr text but
# not the exit code, so the script died before reaching its own $LASTEXITCODE check and wrote no log
# line at all - which reads downstream as "the hook never fired" rather than "the hook crashed".
# Always test $LASTEXITCODE explicitly instead. Harmless on 5.1 and 7.0-7.2, where it is unused.
$PSNativeCommandUseErrorActionPreference = $false

# ...but that variable does not exist in Windows PowerShell 5.1, and 5.1 is what the Copilot host
# actually launches hooks with. 5.1 converts a native command's STDERR into an ErrorRecord, and under
# $ErrorActionPreference = 'Stop' that record is TERMINATING - no non-zero exit required. pnpm writes
# its command banner ("$ eslint .") to stderr on every single run, so the lint step died there every
# time while passing cleanly under pwsh 7. Verified both ways on 2026-07-27.
#
# The preference has to be genuinely lowered around the call, because the error is raised inside
# pnpm's own pnpm.ps1 wrapper, which inherits this scope. Coercing ErrorRecords to strings matters
# too: left as records, they re-throw the moment anything downstream touches them under 'Stop'.
function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string[]]$Arguments = @()
  )
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & $Command @Arguments 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { [string]$_ }
    }
    $code = $LASTEXITCODE
    return [PSCustomObject]@{ Output = @($out); ExitCode = $code }
  } catch {
    return [PSCustomObject]@{ Output = @($_.Exception.Message); ExitCode = 1 }
  } finally {
    $ErrorActionPreference = $prev
  }
}

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


if ($env:SKIP_BUILD_GATE -eq 'true') {
  Write-Host "[SKIP]  Build gate skipped (SKIP_BUILD_GATE=true)"
  exit 0
}

if (-not (Test-Path -LiteralPath 'package.json')) {
  Write-Host "[SKIP]  Build gate skipped (no package.json - not a Node project)"
  exit 0
}

# This hook is registered on BOTH sessionEnd and Stop. In VS Code Copilot Chat sessionEnd never
# fires but Stop fires after EVERY completed turn - so without throttling a full tsc + lint would
# run after every message. Verified live via the event probe (docs/reference/event-probe.md).
# Throttle by timestamp file: run at most once per GATE_MIN_INTERVAL_SEC.
$MinInterval = if ($env:GATE_MIN_INTERVAL_SEC) { [int]$env:GATE_MIN_INTERVAL_SEC } else { 180 }
$stampDir = if ($env:GATE_LOG_DIR) { $env:GATE_LOG_DIR } else { 'logs/copilot/build-gate' }
$stampFile = [System.IO.Path]::Combine($stampDir, '.last-run')
# Store Unix epoch seconds, same as the bash twin. An ISO string round-tripped through
# [datetime]::Parse comes back as Local kind, so subtracting it from a UTC 'now' is off by the
# timezone offset - observed as a negative elapsed time (-7196s on UTC+2).
if ($MinInterval -gt 0 -and (Test-Path -LiteralPath $stampFile)) {
  try {
    $last = [int64](Get-Content -LiteralPath $stampFile -Raw).Trim()
    $elapsed = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $last
    if ($elapsed -lt $MinInterval) {
      Write-Host ("[SKIP]  Build gate throttled ({0}s since last run, minimum {1}s). Set GATE_MIN_INTERVAL_SEC=0 to disable." -f [int]$elapsed, $MinInterval)
      exit 0
    }
  } catch { }
}
try {
  if (-not (Test-Path -LiteralPath $stampDir)) { New-Item -ItemType Directory -Path $stampDir -Force -ErrorAction Stop | Out-Null }
  [System.IO.File]::WriteAllText($stampFile, [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
} catch { }

$Mode = if ($env:GATE_MODE) { $env:GATE_MODE } else { 'warn' }
$LogDir = if ($env:GATE_LOG_DIR) { $env:GATE_LOG_DIR } else { 'logs/copilot/build-gate' }
$RunLint = if ($env:GATE_RUN_LINT) { $env:GATE_RUN_LINT } else { 'true' }
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
# Best-effort: Write-HookLog creates this lazily too. Must not throw - a failed
# mkdir under ErrorActionPreference='Stop' would exit non-zero and, on preToolUse,
# block the tool call outright.
try { New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction Stop | Out-Null } catch { }
$LogFile = [System.IO.Path]::Combine($LogDir, 'gate.log')

# Detect package manager from lockfile - don't assume pnpm/npm/yarn.
$PM = 'npm'
if (Test-Path -LiteralPath 'pnpm-lock.yaml') { $PM = 'pnpm' }
elseif (Test-Path -LiteralPath 'yarn.lock') { $PM = 'yarn' }
elseif (Test-Path -LiteralPath 'package-lock.json') { $PM = 'npm' }

$Failures = @()
$TypecheckRan = $false
$LintRan = $false

# ---------------------------------------------------------------------------
# Type check
# ---------------------------------------------------------------------------
if (Test-Path -LiteralPath 'tsconfig.json') {
  $TypecheckRan = $true
  # A root tsconfig.json using project references (common in Vite scaffolds: "files": [] plus
  # "references": [...]) is NOT traversed by plain `tsc --noEmit` - only `tsc --build` (-b) follows
  # references. Individual referenced tsconfigs in the Vite template already set "noEmit": true, so
  # -b alone (no --noEmit flag, which build mode doesn't reliably honor anyway) won't emit output.
  $usesReferences = Select-String -LiteralPath 'tsconfig.json' -Pattern '"references"' -Quiet -ErrorAction SilentlyContinue
  if ($usesReferences) {
    Write-Host "[CHECK] Running tsc -b (project references detected) ..."
    $tsc = Invoke-NativeCommand -Command 'npx' -Arguments @('--no-install', 'tsc', '-b')
    if ($tsc.ExitCode -ne 0) {
      $tsc.Output | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
      $Failures += 'typecheck'
    }
  } else {
    Write-Host "[CHECK] Running tsc --noEmit ..."
    $tsc = Invoke-NativeCommand -Command 'npx' -Arguments @('--no-install', 'tsc', '--noEmit')
    if ($tsc.ExitCode -ne 0) {
      $tsc.Output | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
      $Failures += 'typecheck'
    }
  }
}

# ---------------------------------------------------------------------------
# Lint (only if the project actually defines a lint script)
# ---------------------------------------------------------------------------
if ($RunLint -eq 'true' -and (Get-Command node -ErrorAction SilentlyContinue)) {
  $hasLintScript = $false
  try {
    $pkg = Get-Content -LiteralPath 'package.json' -Raw | ConvertFrom-Json
    $hasLintScript = [bool]($pkg.scripts -and $pkg.scripts.lint)
  } catch { $hasLintScript = $false }

  if ($hasLintScript) {
    $LintRan = $true
    Write-Host "[CHECK] Running $PM run lint ..."
    $lint = Invoke-NativeCommand -Command $PM -Arguments @('run', 'lint')
    if ($lint.ExitCode -ne 0) {
      $lint.Output | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
      $Failures += 'lint'
    }
  }
}

# ---------------------------------------------------------------------------
# Convention checks - mechanical only, informational by default
# ---------------------------------------------------------------------------
# These exist because some conventions cannot be enforced by instruction prose. The Tailwind check
# was added after that instruction failed to bind in six separate contexts (direct prompt, planning,
# TDD execution, refactor, checklist review, code review). A component can emit Tailwind classes into
# a project with no Tailwind installed and it will compile, typecheck, lint, build and pass every
# test while rendering completely unstyled. No other gate here can see that.
# Every check must be mechanical - no judgement calls. Informational unless GATE_CONVENTIONS=block.
$ConventionMode = if ($env:GATE_CONVENTIONS) { $env:GATE_CONVENTIONS } else { 'warn' }
$Conventions = @()

if ($ConventionMode -ne 'off' -and (Test-Path -LiteralPath 'src')) {
  # Each file is judged against its NEAREST package.json, not the root one. In a repository whose
  # app sits in a subfolder (src/frontend/ with its own package.json), the root package.json lists
  # neither tailwindcss nor tailwind-merge, so both checks below used to fire on a correctly set-up
  # app. node_modules is skipped. Fallback: the root package.json.
  $repoRoot = (Get-Location).Path
  $pkgCache = @{}
  function Get-NearestPackageJson {
    param([string]$FilePath)
    $dir = [System.IO.Path]::GetDirectoryName($FilePath)
    while ($dir -and $dir.Length -ge $repoRoot.Length) {
      $candidate = [System.IO.Path]::Combine($dir, 'package.json')
      if (Test-Path -LiteralPath $candidate) { return $candidate }
      $dir = [System.IO.Path]::GetDirectoryName($dir)
    }
    return [System.IO.Path]::Combine($repoRoot, 'package.json')
  }
  function Test-DeclaresAny {
    param([string]$FilePath, [string]$NamesPattern)
    $pkgPath = Get-NearestPackageJson $FilePath
    if (-not $pkgCache.ContainsKey($pkgPath)) {
      $raw = ''
      try { $raw = Get-Content -LiteralPath $pkgPath -Raw -ErrorAction Stop } catch { $raw = '' }
      $pkgCache[$pkgPath] = $raw
    }
    return ($pkgCache[$pkgPath] -match ('"(' + $NamesPattern + ')"\s*:'))
  }

  $srcFiles = @()
  try {
    $srcFiles = @(Get-ChildItem -Path 'src' -Recurse -File -ErrorAction Stop |
      Where-Object { $_.FullName -notmatch '[\\/]node_modules[\\/]' })
  } catch { }
  $srcTsx = @($srcFiles | Where-Object { $_.Extension -eq '.tsx' -or $_.Extension -eq '.jsx' })

  # 1. Tailwind utility classes emitted into a project with no Tailwind installed.
  #    The suffix list is deliberately restrictive so bespoke class names (my-class, counter,
  #    text-wrapper) do not false-positive - only recognisable Tailwind values count.
  $twValue = '(?:\d+(?:\.\d+)?|px|auto|full|screen|none|xs|sm|md|lg|xl|2xl|3xl|primary|secondary|muted|accent|destructive|foreground|background|center|left|right|start|end|between|around|bold|semibold|medium|light)'
  $twPattern = 'className\s*=[^>]{0,300}?(?:\b(?:flex|grid|hidden|truncate|relative|absolute|sticky)\b|\b(?:bg|text|border|rounded|px|py|pt|pb|pl|pr|mx|my|mt|mb|ml|mr|gap|items|justify|shadow|font|space|inset|w|h|p|m|z)-' + $twValue + '\b)'
  $hits = @()
  foreach ($f in $srcTsx) {
    try {
      if ((Select-String -LiteralPath $f.FullName -Pattern $twPattern -Quiet -ErrorAction Stop) -and
          -not (Test-DeclaresAny $f.FullName 'tailwindcss')) {
        $hits += (Resolve-Path -LiteralPath $f.FullName -Relative)
      }
    } catch { }
  }
  if ($hits.Count -gt 0) {
    $Conventions += [PSCustomObject]@{
      check = 'tailwind_not_installed'
      detail = "Tailwind utility classes found, but 'tailwindcss' is not in the package.json that owns these files. These classes resolve to nothing - the UI renders unstyled and no other check can detect it."
      files = @($hits | Select-Object -First 10)
    }
  }

  # 2. A local cn() helper while nothing merges classes = a hand-rolled stub that concatenates
  #    classes instead of resolving conflicting utilities. tailwind-merge (clsx + twMerge, older
  #    shadcn) and shadcn's own `cn` package (newer shadcn: `export { cn } from "cn"`) both count.
  $cnHits = @()
  foreach ($f in @($srcFiles | Where-Object { $_.Extension -eq '.ts' -or $_.Extension -eq '.tsx' })) {
    if ((Select-String -LiteralPath $f.FullName -Pattern 'export\s+(?:function|const)\s+cn\b' -Quiet -ErrorAction SilentlyContinue) -and
        -not (Test-DeclaresAny $f.FullName 'tailwind-merge|cn')) {
      $cnHits += (Resolve-Path -LiteralPath $f.FullName -Relative)
    }
  }
  if ($cnHits.Count -gt 0) {
    $Conventions += [PSCustomObject]@{
      check = 'cn_without_tailwind_merge'
      detail = "A local cn() helper exists but neither 'tailwind-merge' nor shadcn's 'cn' package is installed, so it concatenates classes instead of resolving conflicts. Install what the project's shadcn version uses (shadcn-ui.instructions.md, Composing)."
      files = @($cnHits | Select-Object -First 10)
    }
  }

  # 3. Components with no colocated test. src/components/ui/** is shadcn CLI output, not ours.
  if (Test-Path -LiteralPath 'src/components') {
    $missingTests = @()
    try {
      foreach ($f in (Get-ChildItem -Path 'src/components' -Recurse -File -ErrorAction Stop |
                      Where-Object { $_.Extension -eq '.tsx' })) {
        if ($f.Name -match '\.(test|spec|stories)\.tsx$') { continue }
        if ($f.FullName.Replace('\', '/') -match '/components/ui/') { continue }
        $testPath = [System.IO.Path]::Combine($f.DirectoryName, ($f.BaseName + '.test.tsx'))
        if (-not (Test-Path -LiteralPath $testPath)) {
          $missingTests += (Resolve-Path -LiteralPath $f.FullName -Relative)
        }
      }
    } catch { }
    if ($missingTests.Count -gt 0) {
      $Conventions += [PSCustomObject]@{
        check = 'component_without_test'
        detail = "Component(s) with no colocated .test.tsx. react-ts.instructions.md lists a colocated test as part of the definition of done."
        files = @($missingTests | Select-Object -First 10)
      }
    }
  }
}

if ($Conventions.Count -gt 0) {
  Write-Host ""
  Write-Host "[WARN] Convention findings ($($Conventions.Count)):"
  foreach ($c in $Conventions) {
    Write-Host "  - $($c.check): $($c.detail)"
    foreach ($file in $c.files) { Write-Host "      $file" }
  }
  if ($ConventionMode -eq 'block') { $Failures += 'conventions' }
  else { Write-Host "  Set GATE_CONVENTIONS=block to fail the gate on these, or =off to disable." }
}

# GATE_CONVENTIONS=block must block on its own. Making it depend on GATE_MODE as well would mean
# setting it to 'block' silently does nothing while GATE_MODE stays 'warn' - two flags whose
# interaction you have to reason about to predict the exit code.
$BlockRequested = ($Mode -eq 'block') -or ($ConventionMode -eq 'block' -and $Conventions.Count -gt 0)

$ConventionNames = @($Conventions | ForEach-Object { $_.check })

if (-not $TypecheckRan -and -not $LintRan -and $Conventions.Count -eq 0) {
  Write-Host "[SKIP]  Nothing to gate (no tsconfig.json, no lint script)"
  [PSCustomObject]@{ timestamp = $Timestamp; event = 'gate_skipped'; mode = $Mode; reason = 'nothing_to_check' } |
    ConvertTo-Json -Compress | Write-HookLog -Path $LogFile
  exit 0
}

if ($Failures.Count -gt 0) {
  [PSCustomObject]@{
    timestamp = $Timestamp; event = 'gate_failed'; mode = $Mode; package_manager = $PM
    failures = $Failures; conventions = $ConventionNames
  } | ConvertTo-Json -Compress | Write-HookLog -Path $LogFile

  Write-Host ""
  Write-Host "[FAIL] Build gate failed: $($Failures -join ', ')"
  if ($BlockRequested) {
    Write-Host "[BLOCKED] Session flagged: fix the above before considering this session's work done."
    Write-Host "  Set GATE_MODE=warn to log without blocking."
    exit 1
  } else {
    Write-Host "[TIP] Set GATE_MODE=block to make this a hard stop instead of a warning."
    exit 0
  }
}

$ConventionNote = if ($Conventions.Count -gt 0) { " - $($Conventions.Count) convention finding(s) above (informational)" } else { '' }
Write-Host "[OK] Build gate passed (typecheck ran: $TypecheckRan, lint ran: $LintRan, via $PM)$ConventionNote"
[PSCustomObject]@{
  timestamp = $Timestamp; event = 'gate_passed'; mode = $Mode; package_manager = $PM
  typecheck_ran = $TypecheckRan; lint_ran = $LintRan; conventions = $ConventionNames
} | ConvertTo-Json -Compress | Write-HookLog -Path $LogFile
exit 0
