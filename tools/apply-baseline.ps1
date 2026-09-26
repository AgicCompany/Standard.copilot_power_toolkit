<#
.SYNOPSIS
  Copy a profile-selected subset of the .github_general baseline into a target project's .github/.

.DESCRIPTION
  Profiles are defined in tools/baseline-profiles.json. A profile decides what gets COPIED — it
  never deletes anything from the baseline itself. Assets that belong to no profile stay here and
  stay linted; they just aren't pushed into projects that have no use for them.

  Project-owned files are protected: copilot-instructions.md and project-context.md are seeded from
  their .template.md counterparts on first apply and are NEVER overwritten afterwards, including
  under -Force. -Force re-syncs baseline-owned assets only.

.PARAMETER Profile
  Which profile to apply. Default: power-apps-code-app. Use -ListProfiles to see all.

.PARAMETER Force
  Overwrite existing baseline-owned files in the target (does not touch project-owned files).

.PARAMETER Prune
  Delete files in the target that came from this baseline but are not in the selected profile.
  Only ever removes paths that exist in the baseline source, so project-authored files are safe.

.PARAMETER DryRun
  Print what would be copied/pruned without touching the filesystem.

.EXAMPLE
  pwsh ./tools/apply-baseline.ps1 -TargetProjectPath ../my-app
  pwsh ./tools/apply-baseline.ps1 -TargetProjectPath ../my-app -Profile react-vite -Force -Prune
  pwsh ./tools/apply-baseline.ps1 -ListProfiles
#>
param(
  [Parameter(Mandatory = $false)]
  [string]$TargetProjectPath,

  # Named ProfileName because PowerShell's built-in automatic variable is literally named Profile
  # (it holds the profile script path); the -Profile alias keeps the ergonomic command-line spelling.
  #
  # Deliberately has NO default here. When omitted, the profile is read from the target's
  # .baseline-manifest.json, so a re-sync keeps whatever profile the project was set up with.
  # Previously this defaulted to power-apps-code-app, which meant a plain `-Force` re-sync on a
  # react-vite project silently switched it to power-apps-code-app and injected Dataverse
  # instructions into a project with no Dataverse.
  [Alias('Profile')]
  [string]$ProfileName,

  # Which UI library the project uses. shadcn is the default and needs no flag.
  #
  # These are mutually exclusive, not additive: shadcn-ui.instructions.md and
  # fluent-ui-v9.instructions.md both declare applyTo '**/*.{tsx,jsx}', so shipping both would put
  # two competing design systems in front of Copilot on every component file with nothing to
  # arbitrate between them. Before this switch existed, choosing Fluent meant hand-editing .github/
  # after applying — which the next -Force re-sync silently undid.
  #
  # Like -Profile, an omitted value is read back from .baseline-manifest.json so a re-sync keeps
  # whatever the project was set up with.
  [ValidateSet('shadcn', 'fluent')]
  [string]$Ui,

  [switch]$Force,
  [switch]$Prune,
  [switch]$DryRun,
  [switch]$ListProfiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info {
  param([string]$Message)
  Write-Host "[baseline] $Message"
}

# Baseline-relative glob -> anchored regex. '**/' spans any number of directories, '**' spans
# anything, '*' stays within a single path segment.
function Convert-GlobToRegex {
  param([string]$Glob)
  $pattern = [regex]::Escape($Glob)
  $pattern = $pattern -replace '\\\*\\\*/', '(?:.*/)?'
  $pattern = $pattern -replace '\\\*\\\*', '.*'
  $pattern = $pattern -replace '\\\*', '[^/]*'
  return "^$pattern$"
}

function Test-MatchesAny {
  param([string]$Path, [string[]]$Patterns)
  foreach ($p in $Patterns) {
    if ($Path -match (Convert-GlobToRegex $p)) { return $true }
  }
  return $false
}

# Substring-based relative paths break whenever the two paths disagree on form — most commonly when
# one side has been resolved to an 8.3 short name (C:\Users\LONGNA~1\...) and the other hasn't, which
# silently yields a garbage relative path rather than an error. GetRelativePath normalises both.
function Get-RelPath {
  param([string]$Base, [string]$Full)
  return ([System.IO.Path]::GetRelativePath($Base, $Full)).Replace('\', '/')
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baselineRoot = Split-Path -Parent $scriptDir
$manifestPath = Join-Path $scriptDir 'baseline-profiles.json'

if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "Profile manifest not found: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

if ($ListProfiles) {
  Write-Host ''
  Write-Host 'Available profiles:' -ForegroundColor Cyan
  foreach ($name in $manifest.profiles.PSObject.Properties.Name) {
    $p = $manifest.profiles.$name
    $extends = if ($p.PSObject.Properties.Name -contains 'extends') { " (extends $($p.extends))" } else { '' }
    Write-Host ""
    Write-Host "  $name$extends" -ForegroundColor Green
    Write-Host "    $($p.description)"
  }
  Write-Host ''
  exit 0
}

if (-not $TargetProjectPath) {
  throw "-TargetProjectPath is required (or use -ListProfiles)."
}
# Resolve the profile: explicit -Profile wins; otherwise reuse what this target was last applied
# with; otherwise fall back to the default for a brand-new project.
$profileSource = 'explicit -Profile'
$uiSource = 'explicit -Ui'
if (-not $ProfileName -or -not $Ui) {
  $receiptPath = Join-Path (Join-Path $TargetProjectPath '.github') '.baseline-manifest.json'
  if (Test-Path -LiteralPath $receiptPath) {
    try {
      $prior = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
      if (-not $ProfileName -and $prior.profile) {
        $ProfileName = $prior.profile
        $profileSource = "remembered from .baseline-manifest.json"
      }
      # PSObject check first: a receipt written before -Ui existed has no such property, and
      # StrictMode turns a bare access into a terminating error rather than $null.
      if (-not $Ui -and $prior.PSObject.Properties.Name -contains 'ui' -and $prior.ui) {
        $Ui = $prior.ui
        $uiSource = "remembered from .baseline-manifest.json"
      }
    } catch {
      Write-Info "Could not read $receiptPath - falling back to the default profile."
    }
  }
}
if (-not $Ui) {
  $Ui = 'shadcn'
  $uiSource = 'default'
}
if (-not $ProfileName) {
  $ProfileName = 'power-apps-code-app'
  $profileSource = 'default (new project)'
}

if ($manifest.profiles.PSObject.Properties.Name -notcontains $ProfileName) {
  throw "Unknown profile '$ProfileName'. Known: $($manifest.profiles.PSObject.Properties.Name -join ', ')"
}

# Resolve profile inheritance into one flat include list.
function Resolve-ProfileIncludes {
  param([string]$Name, [System.Collections.Generic.HashSet[string]]$Seen)
  if (-not $Seen.Add($Name)) {
    throw "Circular 'extends' chain in baseline-profiles.json at profile '$Name'"
  }
  $p = $manifest.profiles.$Name
  $includes = @()
  if ($p.PSObject.Properties.Name -contains 'extends' -and $p.extends) {
    $includes += Resolve-ProfileIncludes -Name $p.extends -Seen $Seen
  }
  $includes += $p.include
  return $includes
}

$includePatterns = @($manifest.common) + (Resolve-ProfileIncludes -Name $ProfileName -Seen ([System.Collections.Generic.HashSet[string]]::new()))
$excludePatterns = @($manifest.alwaysExcluded)

# ---- UI library swap ----------------------------------------------------------------------------
# Applied after inheritance is flattened, so it overrides whatever react-vite contributed. The table
# lives in baseline-profiles.json so lint-baseline.ps1 reads the same source and these files do not
# register as orphaned.
if ($manifest.PSObject.Properties.Name -notcontains 'uiVariants' -or
    $manifest.uiVariants.PSObject.Properties.Name -notcontains $Ui) {
  throw "No uiVariants entry for '$Ui' in baseline-profiles.json."
}
$swap = $manifest.uiVariants.$Ui
$includePatterns = @($includePatterns | Where-Object { $swap.remove -notcontains $_ }) + @($swap.add)
$includePatterns = $includePatterns | Sort-Object -Unique

if (-not (Test-Path -LiteralPath $TargetProjectPath)) {
  throw "Target project path does not exist: $TargetProjectPath"
}

$targetProject = (Resolve-Path -LiteralPath $TargetProjectPath).Path
$targetGithub = Join-Path $targetProject '.github'

Write-Info "Source baseline: $baselineRoot"
Write-Info "Target project:  $targetProject"
Write-Info "Profile:         $ProfileName  [$profileSource]"
Write-Info "UI library:      $Ui  [$uiSource]"
if ($DryRun) { Write-Info 'DRY RUN — no files will be written.' }

# Files whose target counterpart belongs to the PROJECT, not the baseline. Seeded once from a
# template, never overwritten afterwards — not even with -Force. Overwriting these was a real bug:
# a -Force re-sync used to replace a project's tailored copilot-instructions.md with the generic
# template, because the old guard checked the baseline folder for a file that only ever exists in
# the target.
# Keys are relative paths from the baseline root, forward-slashed (see Get-RelPath).
$templateMap = @{
  'copilot-instructions.template.md'   = 'copilot-instructions.md'
  'project-context.template.md'        = 'project-context.md'
  # project-memory.md was shipped as a plain file until 2026-08-03, so every `-Force` re-sync
  # silently replaced the project's accumulated memory with the empty template. Verified with a
  # canary entry: written, re-applied, gone. That is the same bug this map already existed to fix
  # for copilot-instructions.md, on the one file whose entire purpose is to survive sessions.
  'docs/project-memory.template.md'    = 'docs/project-memory.md'
  # The guard's only escape hatch. It lived in the `env` block of hooks/vite-env-guard.json, which is
  # baseline-owned - so a legitimate exception was erased on the next -Force sync, and needed a host
  # reload before it applied at all. An agent hit exactly that on 2026-08-03, concluded the sanctioned
  # path was broken, and bypassed the guard through the terminal instead.
  'vite-env-guard.allow.template'      = 'vite-env-guard.allow'
}

$sourceFiles = Get-ChildItem -LiteralPath $baselineRoot -Recurse -File

$copied = 0
$skippedExisting = 0
$notInProfile = 0
$protectedFiles = @()
$templateDrift = @()
$templateHashes = @{}
$appliedPaths = [System.Collections.Generic.List[string]]::new()

# Prior receipt: used to detect that a project-owned template changed upstream since seeding.
$priorReceipt = $null
$priorReceiptPath = Join-Path $targetGithub '.baseline-manifest.json'
if (Test-Path -LiteralPath $priorReceiptPath) {
  try { $priorReceipt = Get-Content -LiteralPath $priorReceiptPath -Raw | ConvertFrom-Json } catch { }
}

foreach ($file in $sourceFiles) {
  $rel = Get-RelPath -Base $baselineRoot -Full $file.FullName

  if (Test-MatchesAny -Path $rel -Patterns $excludePatterns) { continue }

  if (-not (Test-MatchesAny -Path $rel -Patterns $includePatterns)) {
    $notInProfile++
    continue
  }

  # .vscode/** is workspace-root config (mcp.json). VS Code does not read it from inside .github/,
  # so it lands at the project root instead.
  if ($rel -like '.vscode/*') {
    $destination = Join-Path $targetProject $rel
    $destRel = $rel
  }
  else {
    $destRel = $rel
    $isProjectOwned = $false

    if ($templateMap.ContainsKey($rel)) {
      $destRel = $templateMap[$rel]
      $isProjectOwned = $true
      # Record the template hash on first seed so later runs can detect upstream changes.
      $templateHashes[$destRel] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }

    $destination = Join-Path $targetGithub $destRel

    # Project-owned: seed once, then hands off permanently.
    if ($isProjectOwned -and (Test-Path -LiteralPath $destination)) {
      $protectedFiles += $destRel

      # Protecting the file is right, but it means template improvements never reach existing
      # projects and nothing says so. Compare the template's hash against the one recorded when this
      # project was seeded and warn if it moved - otherwise the only way to notice is for someone to
      # remember. (Confirmed live: a security rule was fixed in the template, re-synced with -Force,
      # and the project kept the old wording silently through two test runs.)
      $currentHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
      $seededHash = $null
      if ($priorReceipt -and $priorReceipt.PSObject.Properties.Name -contains 'templateHashes') {
        $th = $priorReceipt.templateHashes
        if ($th.PSObject.Properties.Name -contains $destRel) { $seededHash = $th.$destRel }
      }
      if ($seededHash -and $seededHash -ne $currentHash) {
        $templateDrift += $destRel
      }
      $templateHashes[$destRel] = $currentHash
      continue
    }
  }

  $appliedPaths.Add($destRel) | Out-Null

  if ((Test-Path -LiteralPath $destination) -and -not $Force) {
    $skippedExisting++
    continue
  }

  if ($DryRun) {
    Write-Info "would copy: $destRel"
    $copied++
    continue
  }

  $destinationDir = Split-Path -Parent $destination
  if (-not (Test-Path -LiteralPath $destinationDir)) {
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
  }
  Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
  $copied++
}

# ---- Prune: remove baseline-owned files the selected profile no longer includes ----------------
if ($Prune -and (Test-Path -LiteralPath $targetGithub)) {
  # Every path this baseline could ever own in a target, so we never touch project-authored files.
  $baselineOwned = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($file in $sourceFiles) {
    $rel = Get-RelPath -Base $baselineRoot -Full $file.FullName
    if (Test-MatchesAny -Path $rel -Patterns $excludePatterns) { continue }
    if ($rel -like '.vscode/*') { continue }
    if ($templateMap.ContainsKey($rel)) { continue }  # project-owned once seeded — never prune
    [void]$baselineOwned.Add($rel)
  }

  $selected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($p in $appliedPaths) { [void]$selected.Add($p) }

  $pruned = 0
  Get-ChildItem -LiteralPath $targetGithub -Recurse -File | ForEach-Object {
    $relTarget = Get-RelPath -Base $targetGithub -Full $_.FullName
    if ($baselineOwned.Contains($relTarget) -and -not $selected.Contains($relTarget)) {
      if ($DryRun) {
        Write-Info "would prune: $relTarget"
      }
      else {
        Remove-Item -LiteralPath $_.FullName -Force
        Write-Info "pruned: $relTarget"
      }
      $pruned++
    }
  }

  # Legacy layout cleanup: hooks used to live at .github/hooks/<name>/hooks.json. Copilot never
  # discovered those (discovery is flat-only), but stale folders still confuse anyone reading the
  # target, so remove them once the flat files are in place.
  $legacyHooks = Join-Path $targetGithub 'hooks'
  if (Test-Path -LiteralPath $legacyHooks) {
    Get-ChildItem -LiteralPath $legacyHooks -Directory | Where-Object { $_.Name -ne 'scripts' } | ForEach-Object {
      if (Test-Path -LiteralPath (Join-Path $_.FullName 'hooks.json')) {
        if ($DryRun) {
          Write-Info "would remove legacy hook folder: hooks/$($_.Name)/"
        }
        else {
          Remove-Item -LiteralPath $_.FullName -Recurse -Force
          Write-Info "removed legacy hook folder: hooks/$($_.Name)/"
        }
        $pruned++
      }
    }
  }
  # Pruning files leaves behind empty asset folders (e.g. skills/<name>/ with its SKILL.md removed),
  # which read as "this skill exists but is broken" to anyone opening the target. Sweep them.
  if (-not $DryRun) {
    $removedDirs = 1
    while ($removedDirs -gt 0) {
      $removedDirs = 0
      Get-ChildItem -LiteralPath $targetGithub -Recurse -Directory |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
          if (-not (Get-ChildItem -LiteralPath $_.FullName -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $_.FullName -Force
            Write-Info "removed empty folder: $(Get-RelPath -Base $targetGithub -Full $_.FullName)/"
            $script:removedDirs++
          }
        }
    }
  }

  Write-Info "Prune: $pruned item(s)."
}

# ---- Receipt ------------------------------------------------------------------------------------
if (-not $DryRun) {
  $receipt = [ordered]@{
    profile     = $ProfileName
    ui          = $Ui
    appliedUtc  = (Get-Date).ToUniversalTime().ToString('o')
    source      = $baselineRoot
    fileCount      = $appliedPaths.Count
    templateHashes = $templateHashes
    files          = ($appliedPaths | Sort-Object)
  }
  $receiptPath = Join-Path $targetGithub '.baseline-manifest.json'
  if (-not (Test-Path -LiteralPath $targetGithub)) {
    New-Item -ItemType Directory -Path $targetGithub -Force | Out-Null
  }
  $receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $receiptPath -Encoding utf8
}

Write-Host ''
Write-Info "Copied: $copied | Skipped (exists, no -Force): $skippedExisting | Not in profile: $notInProfile"
if ($protectedFiles.Count -gt 0) {
  Write-Info "Protected project-owned files (left untouched): $($protectedFiles -join ', ')"
}
if ($templateDrift.Count -gt 0) {
  Write-Host ""
  Write-Host "[!] TEMPLATE CHANGED UPSTREAM - these project-owned files were NOT updated:" -ForegroundColor Yellow
  foreach ($d in $templateDrift) {
    $tmplName = ($templateMap.GetEnumerator() | Where-Object { $_.Value -eq $d } | Select-Object -First 1).Key
    Write-Host "      .github/$d" -ForegroundColor Yellow
    Write-Host "      review changes:  code --diff `"$(Join-Path $baselineRoot $tmplName)`" `"$(Join-Path $targetGithub $d)`"" -ForegroundColor Yellow
  }
  Write-Host "    These files are yours - apply-baseline will never overwrite them. Merge anything you want by hand." -ForegroundColor Yellow
}
Write-Info 'Done.'
