#Requires -Version 5.1
<#
.SYNOPSIS
  Dependency License Checker Hook (PowerShell) - mirrors check-licenses.sh exactly; keep both in
  sync. Scans newly added dependencies (npm/pip/go/ruby/rust) for license compliance at session end.
.NOTES
  Env vars: LICENSE_MODE (warn|block, default warn), SKIP_LICENSE_CHECK (true to disable),
  LICENSE_LOG_DIR (default logs/copilot/license-checker), BLOCKED_LICENSES (comma-separated SPDX),
  LICENSE_ALLOWLIST (comma-separated package names to skip)
#>

$ErrorActionPreference = 'Stop'

# PowerShell 7.3+ turns a native command's non-zero EXIT CODE into a terminating error whenever
# $ErrorActionPreference is 'Stop'. That is fatal here, because a non-zero exit is the normal signal
# this script exists to read - 'git diff HEAD' exits 128 in a repo with no commits yet, which is the
# usual state of a freshly scaffolded project. Redirecting with 2>$null suppresses the stderr text
# but not the exit code, so the script died before writing any log line at all - which reads
# downstream as "the hook never fired" rather than "the hook crashed".
# Always test $LASTEXITCODE explicitly instead. Harmless on 5.1 and 7.0-7.2, where it is unused.
$PSNativeCommandUseErrorActionPreference = $false

# ...but that variable does not exist in Windows PowerShell 5.1, and 5.1 is what the Copilot host
# launches hooks with. 5.1 turns a native command's STDERR into a TERMINATING ErrorRecord under
# 'Stop' - no non-zero exit needed - and `2>$null` does NOT prevent it (verified 2026-07-27: the
# redirect discards the text, the error record is still raised). The preference must actually be
# lowered around the call. Without this, `git rev-parse --is-inside-work-tree` crashed the script
# whenever it ran outside a repo - i.e. the "skip gracefully, this isn't a repo" path was the one
# path guaranteed to blow up.
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


if ($env:SKIP_LICENSE_CHECK -eq 'true') {
  Write-Host "[SKIP]  License check skipped (SKIP_LICENSE_CHECK=true)"
  exit 0
}

$repoProbe = Invoke-NativeCommand -Command 'git' -Arguments @('rev-parse', '--is-inside-work-tree')
if ($repoProbe.ExitCode -ne 0) {
  Write-Host "[WARN]  Not in a git repository, skipping license check"
  exit 0
}

$Mode = if ($env:LICENSE_MODE) { $env:LICENSE_MODE } else { 'warn' }
$LogDir = if ($env:LICENSE_LOG_DIR) { $env:LICENSE_LOG_DIR } else { 'logs/copilot/license-checker' }
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$FindingCount = 0
# Best-effort: Write-HookLog creates this lazily too. Must not throw - a failed
# mkdir under ErrorActionPreference='Stop' would exit non-zero and, on preToolUse,
# block the tool call outright.
try { New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction Stop | Out-Null } catch { }
$LogFile = [System.IO.Path]::Combine($LogDir, 'check.log')

$DefaultBlocked = @('GPL-2.0','GPL-2.0-only','GPL-2.0-or-later','GPL-3.0','GPL-3.0-only','GPL-3.0-or-later',
  'AGPL-1.0','AGPL-3.0','AGPL-3.0-only','AGPL-3.0-or-later','LGPL-2.0','LGPL-2.1','LGPL-2.1-only',
  'LGPL-2.1-or-later','LGPL-3.0','LGPL-3.0-only','LGPL-3.0-or-later','SSPL-1.0','EUPL-1.1','EUPL-1.2',
  'OSL-3.0','CPAL-1.0','CPL-1.0','CC-BY-SA-4.0','CC-BY-NC-4.0','CC-BY-NC-SA-4.0')

$BlockedList = if ($env:BLOCKED_LICENSES) { $env:BLOCKED_LICENSES -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } } else { $DefaultBlocked }
$Allowlist = if ($env:LICENSE_ALLOWLIST) { $env:LICENSE_ALLOWLIST -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } } else { @() }

function Test-Allowlisted {
  param([string]$Pkg)
  foreach ($e in $Allowlist) { if ($Pkg -eq $e) { return $true } }
  return $false
}

function Test-BlockedLicense {
  param([string]$License)
  $lower = $License.ToLower()
  foreach ($b in $BlockedList) {
    if ($lower -like "*$($b.ToLower())*") { return $true }
  }
  return $false
}

# ---------------------------------------------------------------------------
# Phase 1: detect new dependencies per ecosystem, from added lines in the diff
# ---------------------------------------------------------------------------
# A repo made by 'git init' with nothing committed yet has no HEAD, so every 'git diff HEAD' exits
# 128. That is the normal state of a freshly scaffolded project. Checking --is-inside-work-tree is
# not enough: it succeeds here, because the repository does exist. It just has no commits.
$headProbe = Invoke-NativeCommand -Command 'git' -Arguments @('rev-parse', '--verify', '--quiet', 'HEAD')
$HasCommits = ($headProbe.ExitCode -eq 0)

function Get-AddedLines {
  param([string]$FilePath)
  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { return @() }
  # With no commit to diff against there is no baseline, so every dependency in the file is new.
  # Synthesize the '+' prefix the callers' regexes expect rather than shelling out to a diff that
  # would exit 128 and abort the script.
  if (-not $HasCommits) {
    return @(Get-Content -LiteralPath $FilePath -ErrorAction SilentlyContinue | ForEach-Object { "+$_" })
  }
  $diff = @((Invoke-NativeCommand -Command 'git' -Arguments @('diff', 'HEAD', '--', $FilePath)).Output)
  return @($diff | Where-Object { $_ -match '^\+' -and $_ -notmatch '^\+\+\+' })
}

$NewDeps = @()  # each: @{ Ecosystem; Package }

# A line-based scan cannot tell a dependency from a script: both are "key": "value" pairs, so
# "dev": "vite" and "type": "module" match the same regex as a real package. A hand-maintained
# exclusion list can never be complete - it missed "type", "dev", "build", "lint" and "preview" on a
# stock Vite scaffold. Instead, cross-check each candidate against the dependency blocks package.json
# actually declares. This matters most on the no-commits path, where the whole file is treated as
# added and every script would otherwise be reported as a new dependency.
$DeclaredDeps = @{}
if (Test-Path -LiteralPath 'package.json') {
  try {
    $pkgJson = Get-Content -LiteralPath 'package.json' -Raw | ConvertFrom-Json
    foreach ($block in 'dependencies','devDependencies','peerDependencies','optionalDependencies') {
      if ($pkgJson.$block) {
        foreach ($p in $pkgJson.$block.PSObject.Properties.Name) { $DeclaredDeps[$p] = $true }
      }
    }
  } catch { }
}

# npm / yarn / pnpm - package.json
foreach ($line in (Get-AddedLines 'package.json')) {
  $m = [regex]::Match($line, '^\+\s*"([^"]*)"\s*:\s*"[^"]*"')
  if ($m.Success) {
    $pkg = $m.Groups[1].Value
    if ($pkg -and $DeclaredDeps.ContainsKey($pkg)) {
      $NewDeps += @{ Ecosystem = 'npm'; Package = $pkg }
    }
  }
}

# pip - requirements.txt
foreach ($line in (Get-AddedLines 'requirements.txt')) {
  $clean = $line -replace '^\+', ''
  if ($clean -match '^\s*#') { continue }
  if (-not $clean.Trim()) { continue }
  $pkg = ($clean -replace '\s*[><=!~].*', '').Trim()
  if ($pkg) { $NewDeps += @{ Ecosystem = 'pip'; Package = $pkg } }
}

# pip - pyproject.toml
foreach ($line in (Get-AddedLines 'pyproject.toml')) {
  $m = [regex]::Match($line, '^\+\s*"([A-Za-z0-9_-]*)')
  if ($m.Success -and $m.Groups[1].Value) { $NewDeps += @{ Ecosystem = 'pip'; Package = $m.Groups[1].Value } }
}

# Go - go.mod
foreach ($line in (Get-AddedLines 'go.mod')) {
  $m = [regex]::Match($line, '^\+\s*([a-zA-Z0-9._/-]*\.[a-zA-Z0-9._/-]*)\s')
  if ($m.Success) {
    $pkg = $m.Groups[1].Value
    if ($pkg -and $pkg -notin @('module','go','require')) { $NewDeps += @{ Ecosystem = 'go'; Package = $pkg } }
  }
}

# Ruby - Gemfile
foreach ($line in (Get-AddedLines 'Gemfile')) {
  $m = [regex]::Match($line, "^\+\s*gem\s*['" + '"`' + "]([^'" + '"`' + "]*)")
  if ($m.Success -and $m.Groups[1].Value) { $NewDeps += @{ Ecosystem = 'ruby'; Package = $m.Groups[1].Value } }
}

# Rust - Cargo.toml
foreach ($line in (Get-AddedLines 'Cargo.toml')) {
  $m = [regex]::Match($line, '^\+\s*([a-zA-Z0-9_-]*)\s*=')
  if ($m.Success) {
    $pkg = $m.Groups[1].Value
    if ($pkg -and $pkg -notin @('name','version','edition','authors','description','license','repository','rust-version')) {
      $NewDeps += @{ Ecosystem = 'rust'; Package = $pkg }
    }
  }
}

if ($NewDeps.Count -eq 0) {
  Write-Host "[OK] No new dependencies detected"
  [PSCustomObject]@{ timestamp = $Timestamp; event = 'license_check_complete'; mode = $Mode; status = 'clean'; dependencies_checked = 0 } |
    ConvertTo-Json -Compress | Write-HookLog -Path $LogFile
  exit 0
}

Write-Host "[CHECK] Checking licenses for $($NewDeps.Count) new dependency(ies)..."

# ---------------------------------------------------------------------------
# Phase 2: look up license per dependency
# ---------------------------------------------------------------------------
function Get-PackageLicense {
  param([string]$Ecosystem, [string]$Pkg)
  $license = 'UNKNOWN'

  switch ($Ecosystem) {
    'npm' {
      $pkgJsonPath = [System.IO.Path]::Combine("node_modules/$Pkg", 'package.json')
      if (Test-Path -LiteralPath $pkgJsonPath) {
        try {
          $pj = Get-Content -LiteralPath $pkgJsonPath -Raw | ConvertFrom-Json
          if ($pj.license) { $license = [string]$pj.license }
        } catch { }
      }
      if ($license -eq 'UNKNOWN' -and (Get-Command npm -ErrorAction SilentlyContinue)) {
        try {
          $viewResult = (Invoke-NativeCommand -Command 'npm' -Arguments @('view', $Pkg, 'license')).Output
          if ($viewResult) { $license = ($viewResult | Select-Object -First 1).ToString() }
        } catch { }
      }
    }
    'pip' {
      $pipCmd = if (Get-Command pip -ErrorAction SilentlyContinue) { 'pip' } elseif (Get-Command pip3 -ErrorAction SilentlyContinue) { 'pip3' } else { $null }
      if ($pipCmd) {
        try {
          $show = & $pipCmd show $Pkg 2>$null
          $licenseLine = $show | Where-Object { $_ -match '^License:' } | Select-Object -First 1
          if ($licenseLine) { $license = ($licenseLine -replace '^[Ll]icense:\s*', '').Trim() }
        } catch { }
      }
    }
    'go' {
      $gopath = if ($env:GOPATH) { $env:GOPATH } else { [System.IO.Path]::Combine($HOME, 'go') }
      $modCache = [System.IO.Path]::Combine($gopath, 'pkg/mod')
      if (Test-Path -LiteralPath $modCache) {
        $found = Get-ChildItem -Path $modCache -Directory -Recurse -Depth 4 -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -like "*$Pkg@*" } | Select-Object -First 1
        if ($found) {
          $licFile = Get-ChildItem -Path $found.FullName -Filter 'LICENSE*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
          if ($licFile) {
            $content = Get-Content -LiteralPath $licFile.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match 'GNU GENERAL PUBLIC LICENSE') {
              if ($content -match 'Version 3') { $license = 'GPL-3.0' }
              elseif ($content -match 'Version 2') { $license = 'GPL-2.0' }
              else { $license = 'GPL' }
            } elseif ($content -match 'GNU LESSER GENERAL PUBLIC') { $license = 'LGPL' }
            elseif ($content -match 'GNU AFFERO GENERAL PUBLIC') { $license = 'AGPL-3.0' }
            elseif ($content -match 'MIT License') { $license = 'MIT' }
            elseif ($content -match 'Apache License') { $license = 'Apache-2.0' }
            elseif ($content -match 'BSD') { $license = 'BSD' }
          }
        }
      }
    }
    'ruby' {
      if (Get-Command gem -ErrorAction SilentlyContinue) {
        try {
          $spec = & gem spec $Pkg license 2>$null | Where-Object { $_ -notmatch '^---' -and $_ -notmatch '^\.\.\.' } | Select-Object -First 1
          if ($spec) { $license = ($spec -replace '^- ', '').Trim() }
          if (-not $license) { $license = 'UNKNOWN' }
        } catch { }
      }
    }
    'rust' {
      if (Get-Command cargo -ErrorAction SilentlyContinue) {
        try {
          $meta = & cargo metadata --format-version 1 2>$null | ConvertFrom-Json
          $match = $meta.packages | Where-Object { $_.name -eq $Pkg } | Select-Object -First 1
          if ($match -and $match.license) { $license = [string]$match.license }
        } catch { }
      }
    }
  }

  $license = $license.Trim()
  if (-not $license) { $license = 'UNKNOWN' }
  return $license
}

$Results = @()  # @{ Ecosystem; Package; License }
foreach ($dep in $NewDeps) {
  $license = Get-PackageLicense -Ecosystem $dep.Ecosystem -Pkg $dep.Package
  $Results += @{ Ecosystem = $dep.Ecosystem; Package = $dep.Package; License = $license }
}

# ---------------------------------------------------------------------------
# Phase 3 & 4: check against blocked list and allowlist
# ---------------------------------------------------------------------------
$Violations = @()
foreach ($r in $Results) {
  if ($Allowlist.Count -gt 0 -and (Test-Allowlisted -Pkg $r.Package)) { continue }
  if (Test-BlockedLicense -License $r.License) {
    $Violations += $r
    $FindingCount++
  }
}

# ---------------------------------------------------------------------------
# Phase 5: output & logging
# ---------------------------------------------------------------------------
Write-Host ""
" {0,-30} {1,-12} {2,-30} {3}" -f "PACKAGE", "ECOSYSTEM", "LICENSE", "STATUS" | Write-Host
" {0,-30} {1,-12} {2,-30} {3}" -f "-------", "---------", "-------", "------" | Write-Host

foreach ($r in $Results) {
  $status = 'OK'
  if ($Allowlist.Count -gt 0 -and (Test-Allowlisted -Pkg $r.Package)) { $status = 'ALLOWLISTED' }
  elseif (Test-BlockedLicense -License $r.License) { $status = 'BLOCKED' }
  " {0,-30} {1,-12} {2,-30} {3}" -f $r.Package, $r.Ecosystem, $r.License, $status | Write-Host
}
Write-Host ""

$FindingsForLog = $Violations | ForEach-Object { [PSCustomObject]@{ package = $_.Package; ecosystem = $_.Ecosystem; license = $_.License; status = 'BLOCKED' } }
[PSCustomObject]@{
  timestamp = $Timestamp; event = 'license_check_complete'; mode = $Mode
  dependencies_checked = $Results.Count; violation_count = $FindingCount; violations = $FindingsForLog
} | ConvertTo-Json -Compress -Depth 5 | Write-HookLog -Path $LogFile

if ($FindingCount -gt 0) {
  Write-Host "[WARN]  Found $FindingCount license violation(s):"
  Write-Host ""
  foreach ($v in $Violations) {
    Write-Host " - $($v.Package) ($($v.Ecosystem)): $($v.License)"
  }
  Write-Host ""
  if ($Mode -eq 'block') {
    Write-Host "[BLOCKED] Session blocked: resolve license violations above before committing."
    Write-Host "  Set LICENSE_MODE=warn to log without blocking, or add packages to LICENSE_ALLOWLIST."
    exit 1
  } else {
    Write-Host "[TIP] Review the violations above. Set LICENSE_MODE=block to prevent commits with license issues."
  }
} else {
  Write-Host "[OK] All $($Results.Count) dependencies have compliant licenses"
}

exit 0
