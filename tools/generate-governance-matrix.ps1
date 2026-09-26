<#
.SYNOPSIS
  Regenerate GOVERNANCE_MATRIX.md from what is actually on disk and in tools/baseline-profiles.json.

.DESCRIPTION
  The matrix was previously maintained by hand and drifted to ~25% accurate — it listed 6 of 26
  instructions, 5 of 15 agents, 3 of 16 skills. A registry that stale is worse than none, because it
  is trusted. Generating it removes the failure mode entirely.

  Run after adding or removing any baseline asset:
    pwsh ./tools/generate-governance-matrix.ps1

  -Check exits 1 if the file on disk differs from what would be generated (for lint-baseline.ps1).
#>
param([switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$manifest = Get-Content -LiteralPath (Join-Path $root 'tools/baseline-profiles.json') -Raw | ConvertFrom-Json

function Convert-GlobToRegex {
  param([string]$Glob)
  $p = [regex]::Escape($Glob)
  $p = $p -replace '\\\*\\\*/', '(?:.*/)?'
  $p = $p -replace '\\\*\\\*', '.*'
  $p = $p -replace '\\\*', '[^/]*'
  return "^$p$"
}

# Which profiles ship a given relative path (excluding the catch-all 'full').
function Get-ProfilesFor {
  param([string]$Rel)
  $hit = @()
  foreach ($pat in @($manifest.common)) {
    if ($Rel -match (Convert-GlobToRegex $pat)) { return @('all') }
  }
  foreach ($name in $manifest.profiles.PSObject.Properties.Name) {
    $inc = @($manifest.profiles.$name.include)
    if ($inc.Count -eq 1 -and $inc[0] -eq '**') { continue }
    foreach ($pat in $inc) {
      if ($Rel -match (Convert-GlobToRegex $pat)) { $hit += $name; break }
    }
  }
  # power-apps-code-app extends react-vite, so react-vite membership implies both.
  if ($hit -contains 'react-vite' -and $hit -notcontains 'power-apps-code-app') {
    $hit += 'power-apps-code-app'
  }
  if ($hit.Count -eq 0) { return @('full only') }
  return ($hit | Sort-Object -Unique)
}

function Get-Frontmatter {
  param([string]$Path, [string]$Key)
  $lines = Get-Content -LiteralPath $Path
  if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') { return '' }
  for ($i = 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq '---') { break }
    if ($lines[$i] -match "^\s*$([regex]::Escape($Key)):\s*(.+)$") {
      return $Matches[1].Trim().Trim("'`"")
    }
  }
  return ''
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# Governance Matrix')
[void]$sb.AppendLine()
[void]$sb.AppendLine('> **Generated file — do not edit by hand.** Regenerate with')
[void]$sb.AppendLine('> `pwsh ./tools/generate-governance-matrix.ps1` after adding or removing a baseline asset.')
[void]$sb.AppendLine('> `lint-baseline.ps1` fails if this file is out of date.')
[void]$sb.AppendLine()
[void]$sb.AppendLine('"Profiles" is which `tools/baseline-profiles.json` profiles copy the asset into a target')
[void]$sb.AppendLine('project. `all` = every profile. `full only` = kept in the baseline but shipped only by the')
[void]$sb.AppendLine('catch-all `full` profile.')
[void]$sb.AppendLine()

$sections = @(
  @{ Title = 'Instructions'; Path = 'instructions'; Filter = '*.instructions.md'; Extra = 'applyTo' },
  @{ Title = 'Agents';       Path = 'agents';       Filter = '*.agent.md';        Extra = '' },
  @{ Title = 'Prompts';      Path = 'prompts';      Filter = '*.prompt.md';       Extra = '' },
  @{ Title = 'Skills';       Path = 'skills';       Filter = 'SKILL.md';          Extra = '' },
  @{ Title = 'Hooks';        Path = 'hooks';        Filter = '*.json';            Extra = '' }
)

foreach ($sec in $sections) {
  [void]$sb.AppendLine("## $($sec.Title)")
  [void]$sb.AppendLine()
  if ($sec.Extra -eq 'applyTo') {
    [void]$sb.AppendLine('| Asset | Auto-applies to | Profiles |')
    [void]$sb.AppendLine('|---|---|---|')
  } else {
    [void]$sb.AppendLine('| Asset | Description | Profiles |')
    [void]$sb.AppendLine('|---|---|---|')
  }

  # -Force: on Linux/macOS a leading dot means hidden, so without it any dot-directory is skipped and
  # the matrix generated in CI differs from the one generated on Windows - making -Check fail for a
  # reason that has nothing to do with the matrix being stale. See lint-baseline.ps1:286.
  $files = Get-ChildItem -LiteralPath (Join-Path $root $sec.Path) -Filter $sec.Filter -File -Recurse -Force |
    Sort-Object FullName
  foreach ($f in $files) {
    $rel = ([System.IO.Path]::GetRelativePath($root, $f.FullName)).Replace('\', '/')
    $profiles = (Get-ProfilesFor $rel) -join ', '

    if ($sec.Extra -eq 'applyTo') {
      $applyTo = Get-Frontmatter $f.FullName 'applyTo'
      $col2 = if ($applyTo) { "``$applyTo``" } else { '_on-demand (no applyTo)_' }
    }
    elseif ($sec.Title -eq 'Hooks') {
      $readme = Join-Path $f.DirectoryName "$($f.BaseName).README.md"
      $col2 = if (Test-Path -LiteralPath $readme) { Get-Frontmatter $readme 'description' } else { '' }
      if (-not $col2) { $col2 = '—' }
    }
    else {
      $col2 = Get-Frontmatter $f.FullName 'description'
      if ($col2.Length -gt 110) { $col2 = $col2.Substring(0, 107) + '...' }
      if (-not $col2) { $col2 = '—' }
      $col2 = $col2 -replace '\|', '\|'
    }
    [void]$sb.AppendLine("| ``$rel`` | $col2 | $profiles |")
  }
  [void]$sb.AppendLine()
}

[void]$sb.AppendLine('## Policies')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Asset | Purpose |')
[void]$sb.AppendLine('|---|---|')
[void]$sb.AppendLine('| `SAFETY_GUARDRAILS.md` | Blocked actions, confirmation-required actions, secret handling |')
[void]$sb.AppendLine('| `docs/WORKFLOW_AUTHORITY.md` | Canonical branching/release model (Gitflow) |')
[void]$sb.AppendLine('| `docs/mcp-servers.md` | MCP server config and known gaps |')
[void]$sb.AppendLine('| `docs/project-memory.md` | Cross-session durable memory store |')
[void]$sb.AppendLine()

$generated = $sb.ToString() -replace "`r`n", "`n"
$targetPath = Join-Path $root 'GOVERNANCE_MATRIX.md'

if ($Check) {
  $current = if (Test-Path -LiteralPath $targetPath) {
    (Get-Content -LiteralPath $targetPath -Raw) -replace "`r`n", "`n"
  } else { '' }
  if ($current.TrimEnd() -ne $generated.TrimEnd()) {
    Write-Host 'GOVERNANCE_MATRIX.md is out of date - run: pwsh ./tools/generate-governance-matrix.ps1' -ForegroundColor Red
    exit 1
  }
  Write-Host 'GOVERNANCE_MATRIX.md is up to date.' -ForegroundColor Green
  exit 0
}

Set-Content -LiteralPath $targetPath -Value $generated -Encoding utf8 -NoNewline
Write-Host "Wrote $targetPath"
