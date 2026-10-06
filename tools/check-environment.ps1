#Requires -Version 5.1
<#
.SYNOPSIS
  Reports which tools this baseline needs, which are present, and how to install the rest.
.DESCRIPTION
  Run this FIRST on a new machine. Written after a real fresh-machine install produced a cascade of
  failures - `pwsh` not recognised, then no pnpm, then a Vite scaffold failing on missing Node
  tooling - each discovered only after the previous one was fixed. A list in a README does not
  prevent that; a command that tells you everything missing at once does.

  Deliberately runs under Windows PowerShell 5.1 as well as pwsh 7, because "pwsh is not recognized"
  is the first error a new user hits - a checker that itself requires pwsh would be useless to them.

  Informational only: never exits non-zero, never installs anything.
.NOTES
  Usage:  powershell -File tools/check-environment.ps1
     or:  pwsh ./tools/check-environment.ps1
     add: -Profile power-apps-code-app   to include the Power Platform tooling
#>

[CmdletBinding()]
param(
  [Alias('Profile')]
  [ValidateSet('react-vite', 'power-apps-code-app', 'power-apps-canvas-migration', 'baseline-authoring', 'full')]
  [string]$ProfileName = 'react-vite'
)

$ErrorActionPreference = 'Continue'

function Get-ToolVersion {
  param([string]$Command, [string[]]$VersionArgs = @('--version'))
  $cmd = Get-Command $Command -ErrorAction SilentlyContinue
  if (-not $cmd) { return $null }
  try {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $out = & $Command @VersionArgs 2>&1 | Select-Object -First 1
    $ErrorActionPreference = $prev
    return ([string]$out).Trim()
  } catch { return '(installed)' }
}

$checks = @(
  @{ Name = 'PowerShell 7+ (pwsh)'; Cmd = 'pwsh'; Args = @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()')
     Required = $true; Profiles = @('*')
     Install = 'winget install --id Microsoft.PowerShell -e'
     Why = 'apply-baseline.ps1, lint-baseline.ps1. Windows ships 5.1 as "powershell" - "pwsh" is a separate install and is NOT present by default.' }

  @{ Name = 'Git'; Cmd = 'git'; Required = $true; Profiles = @('*')
     Install = 'winget install --id Git.Git -e'
     Why = 'cloning this repo; the delivery agent and several hooks shell out to git.' }

  @{ Name = 'Node.js (LTS)'; Cmd = 'node'; Required = $true; Profiles = @('react-vite', 'power-apps-code-app', 'power-apps-canvas-migration', 'full')
     Install = 'winget install --id OpenJS.NodeJS.LTS -e'
     Why = 'Vite, the test runner, and the build-gate/lint-fix hooks (which call npx).' }

  @{ Name = 'pnpm'; Cmd = 'pnpm'; Required = $false; Profiles = @('react-vite', 'power-apps-code-app', 'power-apps-canvas-migration', 'full')
     Install = 'npm install -g pnpm     (or: corepack enable)'
     Why = 'optional - only for a project whose lockfile is pnpm-lock.yaml. The baseline names no package manager: the lockfile decides (docs/reference/package-managers.md), and npm ships with Node.' }

  @{ Name = 'Yarn'; Cmd = 'yarn'; Required = $false; Profiles = @('react-vite', 'power-apps-code-app', 'power-apps-canvas-migration', 'full')
     Install = 'corepack enable     (Yarn 2+ reads its version from package.json "packageManager")   or: npm install -g yarn   (Yarn 1)'
     Why = 'optional - only for a project whose lockfile is yarn.lock. Yarn 1 and Yarn 2+ take different commands; docs/reference/package-managers.md says how to tell them apart.' }

  @{ Name = 'Power Apps CLI (pa)'; Cmd = 'pa'; Required = $true; Profiles = @('power-apps-code-app', 'power-apps-canvas-migration', 'full')
     Install = 'npm install --global @microsoft/power-apps-cli'
     Why = 'pa app init / add data-source / push. Nothing in the Code App workflow works without it. This REPLACES the legacy pac code commands, which cannot add Dataverse actions or functions at all - a project needing a Custom API must be on pa.' }

  @{ Name = 'Power Platform CLI (pac)'; Cmd = 'pac'; Required = $false; Profiles = @('power-apps-code-app', 'power-apps-canvas-migration', 'full')
     Install = 'dotnet tool install --global Microsoft.PowerApps.CLI.Tool    (or the VS Code Power Platform Tools extension)'
     Why = 'optional - the legacy CLI. Still used for solution-level work (pac solution) that the npm CLI does not cover. Not needed for the code app itself.' }

  @{ Name = 'GitHub CLI (gh)'; Cmd = 'gh'; Required = $false; Profiles = @('*')
     Install = 'winget install --id GitHub.cli -e'
     Why = 'optional - the delivery agent uses it to open pull requests. Without it you get the command and compare URL to run yourself.' }

  @{ Name = 'jq'; Cmd = 'jq'; Required = $false; Profiles = @('*')
     Install = 'winget install --id jqlang.jq -e'
     Why = 'optional on Windows - only the .sh hook variants need it. The .ps1 versions are what run here.' }
)

Write-Host ""
Write-Host "Environment check - profile: $ProfileName" -ForegroundColor Cyan
Write-Host ("-" * 72)

$missingRequired = @()
$missingOptional = @()

foreach ($c in $checks) {
  if ($c.Profiles -notcontains '*' -and $c.Profiles -notcontains $ProfileName) { continue }

  $args = if ($c.ContainsKey('Args')) { $c.Args } else { @('--version') }
  $ver = Get-ToolVersion -Command $c.Cmd -VersionArgs $args

  if ($ver) {
    Write-Host ("  [ok]      {0,-28} {1}" -f $c.Name, $ver) -ForegroundColor Green
  }
  elseif ($c.Required) {
    Write-Host ("  [MISSING] {0,-28} REQUIRED" -f $c.Name) -ForegroundColor Red
    $missingRequired += $c
  }
  else {
    Write-Host ("  [--]      {0,-28} optional, not installed" -f $c.Name) -ForegroundColor DarkGray
    $missingOptional += $c
  }
}

Write-Host ""
if ($missingRequired.Count -gt 0) {
  Write-Host "MISSING REQUIRED TOOLING" -ForegroundColor Red
  Write-Host ("-" * 72)
  foreach ($m in $missingRequired) {
    Write-Host ""
    Write-Host "  $($m.Name)" -ForegroundColor Yellow
    Write-Host "    why:     $($m.Why)"
    Write-Host "    install: $($m.Install)" -ForegroundColor Cyan
  }
  Write-Host ""
  Write-Host "  Install everything above, then RESTART YOUR TERMINAL before re-running -" -ForegroundColor Yellow
  Write-Host "  PATH changes do not reach a shell that is already open." -ForegroundColor Yellow
}
else {
  Write-Host "  All required tooling present for the '$ProfileName' profile." -ForegroundColor Green
  if ($missingOptional.Count -gt 0) {
    Write-Host ""
    foreach ($m in $missingOptional) {
      Write-Host "  optional: $($m.Name) - $($m.Why)" -ForegroundColor DarkGray
      Write-Host "            $($m.Install)" -ForegroundColor DarkGray
    }
  }
  Write-Host ""
  Write-Host "  Next:  pwsh ./tools/apply-baseline.ps1 -TargetProjectPath ""C:\path\to\your-project"" -Profile $ProfileName" -ForegroundColor Cyan
  Write-Host "  Then:  reload the VS Code window (Developer: Reload Window)." -ForegroundColor Cyan
}
Write-Host ""
exit 0
