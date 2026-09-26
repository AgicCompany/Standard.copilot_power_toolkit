<#
.SYNOPSIS
  Local sanity check for .github_general — not a build step, just a fast way to catch the class of
  silent bugs a full manual read would otherwise be needed to find (bad frontmatter fields, dangling
  hook script paths, unconfigured MCP tool references, overly-broad applyTo on large files).

.USAGE
  pwsh ./tools/lint-baseline.ps1
  Exit code 0 = clean, 1 = issues found. Warnings don't affect exit code; errors do.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$errors = @()
$warnings = @()

function Get-FrontmatterLines {
  param([string]$Path)
  $lines = Get-Content -LiteralPath $Path
  if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') { return @() }
  $end = -1
  for ($i = 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq '---') { $end = $i; break }
  }
  if ($end -eq -1) { return @() }
  return $lines[1..($end - 1)]
}

Write-Host "[lint] Checking agents/*.agent.md ..."
Get-ChildItem -LiteralPath (Join-Path $root 'agents') -Filter '*.agent.md' -File | ForEach-Object {
  $fm = Get-FrontmatterLines $_.FullName
  $slug = $_.BaseName -replace '\.agent$', ''

  # Top-level frontmatter keys are unindented; an indented 'agent:' is a handoff target, which is valid.
  if ($fm -match '^agent:\s*') {
    $errors += "agents/$($_.Name): uses non-existent 'agent:' frontmatter field (should be 'name:')"
  }
  if (-not ($fm -match '^\s*description:\s*')) {
    $errors += "agents/$($_.Name): missing required 'description' field"
  }
  $nameLine = $fm | Where-Object { $_ -match '^\s*name:\s*(.+)$' } | Select-Object -First 1
  if ($nameLine) {
    $nameValue = ($nameLine -replace '^\s*name:\s*', '').Trim().Trim("'`"")
    if ($nameValue -match '\s') {
      $errors += "agents/$($_.Name): name: '$nameValue' contains spaces — invocation slugs should be plain lowercase-hyphenated (e.g. matching the filename)"
    }
    elseif ($nameValue -ne $slug) {
      $warnings += "agents/$($_.Name): name '$nameValue' does not match filename slug '$slug' — the picker shows 'name', so the two drifting apart makes the agent hard to find"
    }
  }

  # A pinned model overrides the picker default. Legitimate, but it silently freezes an agent on an
  # older model as newer ones ship, so it should be a conscious choice.
  $modelLine = $fm | Where-Object { $_ -match '^\s*model:\s*(.+)$' } | Select-Object -First 1
  if ($modelLine) {
    $modelValue = ($modelLine -replace '^\s*model:\s*', '').Trim().Trim("'`"")
    $warnings += "agents/$($_.Name): pins model '$modelValue' — overrides the picker default; remove the field unless the pin is deliberate"
  }
}

Write-Host "[lint] Checking prompts/*.prompt.md ..."
$agentSlugs = Get-ChildItem -LiteralPath (Join-Path $root 'agents') -Filter '*.agent.md' -File |
  ForEach-Object { $_.BaseName -replace '\.agent$', '' }
# Built-in chat modes a prompt may target instead of a custom agent.
$builtinModes = @('agent', 'ask', 'edit')

Get-ChildItem -LiteralPath (Join-Path $root 'prompts') -Filter '*.prompt.md' -File | ForEach-Object {
  # @() coercion: Get-FrontmatterLines returns a bare string when the block is one line, and under
  # Set-StrictMode a bare string has no .Count.
  $fm = @(Get-FrontmatterLines $_.FullName)
  if ($fm.Count -eq 0) {
    $errors += "prompts/$($_.Name): no frontmatter — the slash-command picker will show it with no description"
    return
  }
  if (-not ($fm -match '^\s*description:\s*')) {
    $errors += "prompts/$($_.Name): missing required 'description' field"
  }
  $agentLine = $fm | Where-Object { $_ -match '^\s*agent:\s*(.+)$' } | Select-Object -First 1
  if ($agentLine) {
    $agentValue = ($agentLine -replace '^\s*agent:\s*', '').Trim().Trim("'`"")
    if ($builtinModes -notcontains $agentValue -and $agentSlugs -notcontains $agentValue) {
      $errors += "prompts/$($_.Name): agent: '$agentValue' is neither a built-in mode ($($builtinModes -join '/')) nor an agent in agents/ — the prompt silently falls back to the default mode"
    }
  }
}

Write-Host "[lint] Checking instructions/*.instructions.md ..."
Get-ChildItem -LiteralPath (Join-Path $root 'instructions') -Filter '*.instructions.md' -File | ForEach-Object {
  $fm = Get-FrontmatterLines $_.FullName
  $lineCount = (Get-Content -LiteralPath $_.FullName).Count

  if (-not ($fm -match '^\s*description:\s*')) {
    $errors += "instructions/$($_.Name): missing required 'description' field"
  }
  $applyToLine = $fm | Where-Object { $_ -match "^\s*applyTo:\s*['\`"]?\*\*['\`"]?\s*$" }
  if ($applyToLine -and $lineCount -gt 150) {
    $warnings += "instructions/$($_.Name): applyTo is unscoped '**' on a $lineCount-line file — loads into every session regardless of file type; confirm that's intentional"
  }

  # No applyTo means VS Code never auto-applies the file: "If not specified, the instructions are
  # not applied automatically, but you can still add them manually to a chat request." That is a
  # legitimate choice for workflow guidance with no file-pattern trigger (git, work items, DevOps
  # culture) — but it must be deliberate and stated, or the file is simply dead weight nobody
  # notices. Require a 'LOADING:' or 'OPT-IN:' note in the body to prove intent.
  $hasApplyTo = [bool]($fm -match '^\s*applyTo:\s*\S')
  if (-not $hasApplyTo) {
    $body = Get-Content -LiteralPath $_.FullName -Raw
    if ($body -notmatch '(?m)^\s*(LOADING|OPT-IN):') {
      $errors += "instructions/$($_.Name): no 'applyTo' and no 'LOADING:'/'OPT-IN:' note — VS Code will never auto-apply this file, so it silently does nothing. Add an applyTo glob, or document why it's on-demand."
    }
  }

  # Single-star globs match root-level files only — nearly always a typo for '**'.
  $singleStar = $fm | Where-Object { $_ -match "^\s*applyTo:\s*['\`"]?\*['\`"]?\s*$" }
  if ($singleStar) {
    $errors += "instructions/$($_.Name): applyTo is '*' (single star) — matches only root-level files, not a recursive match. Use '**' or a real glob."
  }
}

Write-Host "[lint] Checking hooks/*.json ..."
# Flat structure only: .github/hooks/<name>.json + .github/hooks/scripts/<script>. Confirmed against
# the authoritative GitHub Copilot hooks reference — the host only discovers flat *.json files
# directly under .github/hooks/; it does not recurse into subfolders. A prior version of this
# baseline used .github/hooks/<name>/hooks.json, which the host could never find at all.
$hooksRoot = Join-Path $root 'hooks'
Get-ChildItem -LiteralPath $hooksRoot -Filter '*.json' -File | ForEach-Object {
  $hooksJsonPath = $_.FullName
  $hookName = $_.BaseName
  $readmePath = Join-Path $hooksRoot "$hookName.README.md"

  if (-not (Test-Path -LiteralPath $readmePath)) {
    $errors += "hooks/${hookName}.json: missing sibling ${hookName}.README.md"
  }

  # Event keys differing only by case (postToolUse + PostToolUse) break ConvertFrom-Json outright,
  # and the native error is cryptic. Catch it first with an actionable message. Registering both
  # casings looks like sensible cross-host insurance but is not viable in one file - pick the name
  # verified for your host (VS Code Chat: PostToolUse, Stop) and note the alternative in the README.
  $rawHooks = Get-Content -LiteralPath $hooksJsonPath -Raw
  $eventKeys = [regex]::Matches($rawHooks, '"([A-Za-z]+)"\s*:\s*\[') | ForEach-Object { $_.Groups[1].Value }
  $collisions = $eventKeys | Group-Object { $_.ToLower() } | Where-Object { $_.Count -gt 1 }
  foreach ($c in $collisions) {
    $errors += "hooks/$hookName.json: event keys differing only by case ($($c.Group -join ', ')) - breaks JSON parsing in PowerShell and likely the host. Keep only the name verified for your host and document the alternative."
  }

  try {
    $json = $rawHooks | ConvertFrom-Json -ErrorAction Stop
  } catch {
    $errors += "hooks/$hookName.json: invalid JSON — $($_.Exception.Message)"
    return
  }

  foreach ($eventName in $json.hooks.PSObject.Properties.Name) {
    foreach ($entry in $json.hooks.$eventName) {
      foreach ($shellField in @('bash', 'powershell')) {
        if ($entry.PSObject.Properties.Name -contains $shellField) {
          $scriptRel = $entry.$shellField
          if (-not $scriptRel.StartsWith('.github/hooks/scripts/')) {
            $errors += "hooks/$hookName.json: $shellField script path '$scriptRel' doesn't start with '.github/hooks/scripts/' — will not resolve once copied into a target project's .github/"
          } else {
            $scriptRelFromHooksRoot = $scriptRel -replace '^\.github/hooks/', ''
            $scriptFull = Join-Path $hooksRoot $scriptRelFromHooksRoot
            if (-not (Test-Path -LiteralPath $scriptFull)) {
              $errors += "hooks/$hookName.json: references '$scriptRel' which does not exist"
            }
          }
        }
      }
      # Windows hosts without bash on PATH (no WSL/Git Bash selected) need the powershell field —
      # confirmed empirically that hooks are completely silent without it, not just "less portable".
      if (($entry.PSObject.Properties.Name -contains 'bash') -and ($entry.PSObject.Properties.Name -notcontains 'powershell')) {
        $warnings += "hooks/$hookName.json: has 'bash' but no 'powershell' field — hook will not fire on a native Windows host without bash on PATH"
      }

      # A host-level 'matcher' filters on the TOOL NAME before the script ever runs. Tool names differ
      # between hosts (Copilot CLI vs VS Code Chat) and across versions, so a matcher that doesn't
      # match silently disables the hook - it fails OPEN. Confirmed live: vite-env-guard had
      # matcher 'edit'/'create', never fired in VS Code Chat, and a live-format API key was written
      # to .env.local unblocked. tool-guardian, which has no matcher, fired normally.
      # Filter on the payload inside the script instead - the target path is stable, the tool name is not.
      if ($entry.PSObject.Properties.Name -contains 'matcher') {
        $sev = if ($eventName -eq 'preToolUse') { 'errors' } else { 'warnings' }
        $msg = "hooks/$hookName.json [$eventName]: uses 'matcher: $($entry.matcher)' — matchers filter on tool name, which differs per host/version, so a mismatch silently disables the hook (fails OPEN). Remove the matcher and filter on the payload inside the script."
        if ($sev -eq 'errors') { $errors += $msg } else { $warnings += $msg }
      }
    }
  }
}

Write-Host "[lint] Checking skills/*/SKILL.md ..."
Get-ChildItem -LiteralPath (Join-Path $root 'skills') -Directory | ForEach-Object {
  $skillPath = Join-Path $_.FullName 'SKILL.md'
  if (-not (Test-Path -LiteralPath $skillPath)) {
    $errors += "skills/$($_.Name): missing SKILL.md"
    return
  }
  $fm = Get-FrontmatterLines $skillPath
  if (-not ($fm -match '^\s*name:\s*')) {
    $errors += "skills/$($_.Name)/SKILL.md: missing 'name' field"
  }
  if (-not ($fm -match '^\s*description:\s*')) {
    $errors += "skills/$($_.Name)/SKILL.md: missing 'description' field"
  }

  # AGENTS.md states name must match the folder. Title-case names with spaces drifted in from
  # copied catalogue skills and nothing was checking it.
  $skillNameLine = $fm | Where-Object { $_ -match '^\s*name:\s*(.+)$' } | Select-Object -First 1
  if ($skillNameLine) {
    $skillName = ($skillNameLine -replace '^\s*name:\s*', '').Trim().Trim("'`"")
    if ($skillName -ne $_.Name) {
      $warnings += "skills/$($_.Name)/SKILL.md: name '$skillName' does not match folder '$($_.Name)' — AGENTS.md requires them to match"
    }
  }
}

Write-Host "[lint] Checking MCP tool references against .vscode/mcp.json ..."
$mcpConfigPath = Join-Path $root '.vscode/mcp.json'
$configuredServers = @()
if (Test-Path -LiteralPath $mcpConfigPath) {
  $mcpConfig = Get-Content -LiteralPath $mcpConfigPath -Raw | ConvertFrom-Json
  $configuredServers = $mcpConfig.servers.PSObject.Properties.Name
}
# Bare (unprefixed) built-in tool names/aliases that are genuinely fine as-is — either a bare
# category name itself, or one with no confirmed namespaced form.
$builtinAliases = @('read', 'edit', 'search', 'execute', 'agent', 'web', 'todo',
  'runCommands', 'runTasks', 'runNotebooks', 'findTestFiles', 'changes', 'new', 'openSimpleBrowser',
  'getTerminalOutput', 'runInTerminal')
# category/tool namespaces that are VS Code built-ins, not MCP servers (e.g. search/codebase, web/fetch).
$builtinCategories = @('read', 'edit', 'search', 'execute', 'agent', 'web', 'todo', 'vscode', 'changes')
# VS Code has confirmed (via editor diagnostic, not just docs) that these bare names are renamed —
# e.g. 'editFiles' -> 'edit/editFiles'. A bare hit here is a real bug (tool silently unavailable),
# not just a style nit, so it's an error.
$renamedTools = @{
  'codebase' = 'search/codebase'; 'editFiles' = 'edit/editFiles'; 'fetch' = 'web/fetch'
  'githubRepo' = 'web/githubRepo'; 'problems' = 'read/problems'; 'searchResults' = 'search/searchResults'
  'terminalLastCommand' = 'read/terminalLastCommand'; 'terminalSelection' = 'read/terminalSelection'
  'usages' = 'search/usages'; 'vscodeAPI' = 'vscode/vscodeAPI'; 'testFailure' = 'execute/testFailure'
  'runTests' = 'execute/runTests'; 'extensions' = 'vscode/extensions'
}

Get-ChildItem -LiteralPath (Join-Path $root 'agents') -Filter '*.agent.md' -File | ForEach-Object {
  $fm = Get-FrontmatterLines $_.FullName
  $inTools = $false
  foreach ($line in $fm) {
    if ($line -match '^\s*tools:\s*$') { $inTools = $true; continue }
    if ($inTools) {
      if ($line -match '^\s*#') { continue }
      if ($line -notmatch '^\s*-\s*') { $inTools = $false; continue }
      $tool = ($line -replace '^\s*-\s*', '').Trim().Trim("'`"").TrimStart('/')
      if ($tool -eq '*' -or $builtinAliases -contains $tool) { continue }
      if ($renamedTools.ContainsKey($tool)) {
        $errors += "agents/$($_.Name): tool '$tool' has been renamed by VS Code to '$($renamedTools[$tool])' — bare form silently loses this tool (confirmed via editor diagnostic, not just docs)"
        continue
      }
      if ($tool -match '^([^/]+)/') {
        $prefix = $Matches[1]
        if ($builtinCategories -notcontains $prefix -and $configuredServers -notcontains $prefix) {
          $warnings += "agents/$($_.Name): tools references '$tool' but '$prefix' isn't a built-in category or a server in .vscode/mcp.json"
        }
      } else {
        $warnings += "agents/$($_.Name): tool '$tool' has no server/ prefix and isn't a recognized builtin alias — likely silently ignored. See docs/mcp-servers.md"
      }
    }
  }
}

Write-Host "[lint] Checking tools/baseline-profiles.json ..."
# A profile pattern that matches nothing is the failure mode with no symptom: apply-baseline just
# quietly ships one asset fewer, and you find out when Copilot in the target project doesn't know
# something it should.
$profilesPath = Join-Path $root 'tools/baseline-profiles.json'
if (-not (Test-Path -LiteralPath $profilesPath)) {
  $errors += "tools/baseline-profiles.json: missing — apply-baseline.ps1 cannot run without it"
}
else {
  try {
    $profileManifest = Get-Content -LiteralPath $profilesPath -Raw | ConvertFrom-Json -ErrorAction Stop
  } catch {
    $errors += "tools/baseline-profiles.json: invalid JSON — $($_.Exception.Message)"
    $profileManifest = $null
  }

  if ($profileManifest) {
    # -Force is REQUIRED for cross-platform correctness, not an optimisation. On Linux and macOS a
    # leading dot IS the hidden convention, so without it Get-ChildItem silently skips .vscode/ and
    # .github/ entirely. On Windows "hidden" is a file attribute rather than a naming convention, so
    # the same code enumerates them fine - which is exactly how this shipped green locally and failed
    # on the very first CI run with "pattern '.vscode/**' matches no file in the baseline".
    # .vscode/mcp.json is a real shipped asset in the 'common' profile; it was never actually missing.
    $allRel = Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
      ([System.IO.Path]::GetRelativePath($root, $_.FullName)).Replace('\', '/')
    }

    function Convert-LintGlob {
      param([string]$Glob)
      $p = [regex]::Escape($Glob)
      $p = $p -replace '\\\*\\\*/', '(?:.*/)?'
      $p = $p -replace '\\\*\\\*', '.*'
      $p = $p -replace '\\\*', '[^/]*'
      return "^$p$"
    }

    $covered = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $allPatterns = @()
    $allPatterns += $profileManifest.common
    foreach ($pName in $profileManifest.profiles.PSObject.Properties.Name) {
      $inc = @($profileManifest.profiles.$pName.include)
      # Skip catch-all profiles ('full') when computing coverage — '**' matches everything, which
      # would make the orphan check below vacuously pass for every file in the baseline.
      if ($inc.Count -eq 1 -and $inc[0] -eq '**') { continue }
      $allPatterns += $inc
    }

    # Files a UI variant can add (-Ui fluent) are profile-managed, not orphans. Without this,
    # fluent-ui-v9.instructions.md reads as "belongs to no profile" even though apply-baseline ships
    # it on demand — a warning that trains people to ignore warnings.
    if ($profileManifest.PSObject.Properties.Name -contains 'uiVariants') {
      foreach ($v in $profileManifest.uiVariants.PSObject.Properties.Name) {
        $allPatterns += @($profileManifest.uiVariants.$v.add)
      }
    }

    foreach ($pat in ($allPatterns | Select-Object -Unique)) {
      $rx = Convert-LintGlob $pat
      $hits = @($allRel | Where-Object { $_ -match $rx })
      if ($hits.Count -eq 0) {
        $errors += "baseline-profiles.json: pattern '$pat' matches no file in the baseline — renamed or deleted asset, so the profile silently ships one file fewer"
      }
      foreach ($h in $hits) { [void]$covered.Add($h) }
    }

    # Orphans: present in the baseline but in no profile at all. Not an error (that's the whole
    # point of keeping assets around), but worth surfacing so it stays a decision.
    $excluded = @($profileManifest.alwaysExcluded)
    foreach ($f in $allRel) {
      $isExcluded = $false
      foreach ($ex in $excluded) { if ($f -match (Convert-LintGlob $ex)) { $isExcluded = $true; break } }
      if ($isExcluded) { continue }
      if (-not $covered.Contains($f)) {
        $warnings += "baseline-profiles.json: '$f' belongs to no profile — kept in the baseline but never copied into a project"
      }
    }

    # ---- Handoff targets must exist, and must resolve in every profile that ships the source ----
    #
    # "Handoffs to non-existent agents will be silently ignored" (instructions/agents.instructions.md).
    # Silently. So a typo, a renamed agent, or a target that simply isn't in the same profile produces
    # a button that does nothing and reports nothing - the same invisible-failure class as a hook with
    # a stale matcher or a guard that logs guard_passed while inspecting an empty string.
    #
    # Found on the first run of this rule: plan, small-plan, review and delivery all ship in 'common'
    # and hand off to tdd/checklist, which ship only in 'react-vite'. In a baseline-authoring project
    # every one of those buttons was dead.
    Write-Host "[lint] Checking agent handoff targets resolve ..."

    $agentNames = @{}
    Get-ChildItem -LiteralPath (Join-Path $root 'agents') -Filter '*.agent.md' -File | ForEach-Object {
      $raw = Get-Content -LiteralPath $_.FullName -Raw
      $slug = if ($raw -match "(?m)^name:\s*'?`"?([^'`"\r\n]+)") { $Matches[1].Trim() } else { $_.BaseName -replace '\.agent$', '' }
      $agentNames[$slug] = "agents/$($_.Name)"
    }

    # Which agents does a given profile actually ship? Resolve common + the profile's own includes,
    # following 'extends' so power-apps-code-app inherits react-vite's agents.
    function Get-ProfileAgents {
      param([string]$ProfileName)
      $pats = @($profileManifest.common)
      $seen = @{}
      $cur = $ProfileName
      while ($cur -and -not $seen.ContainsKey($cur)) {
        $seen[$cur] = $true
        $def = $profileManifest.profiles.$cur
        if (-not $def) { break }
        $pats += @($def.include)
        # Under StrictMode, reading a property that isn't declared THROWS rather than returning null -
        # only power-apps-code-app has 'extends', so this must be probed, not accessed.
        $cur = if ($def.PSObject.Properties.Name -contains 'extends') { $def.extends } else { $null }
      }
      $out = @{}
      foreach ($pat in $pats) {
        $rx = Convert-LintGlob $pat
        foreach ($rel in ($agentNames.GetEnumerator())) {
          if ($rel.Value -match $rx) { $out[$rel.Key] = $true }
        }
      }
      return $out
    }

    $profileAgentSets = @{}
    foreach ($pName in $profileManifest.profiles.PSObject.Properties.Name) {
      $inc = @($profileManifest.profiles.$pName.include)
      if ($inc.Count -eq 1 -and $inc[0] -eq '**') { continue }   # 'full' ships everything
      $profileAgentSets[$pName] = Get-ProfileAgents -ProfileName $pName
    }

    Get-ChildItem -LiteralPath (Join-Path $root 'agents') -Filter '*.agent.md' -File | ForEach-Object {
      $file = $_
      $raw = Get-Content -LiteralPath $file.FullName -Raw
      $srcSlug = if ($raw -match "(?m)^name:\s*'?`"?([^'`"\r\n]+)") { $Matches[1].Trim() } else { $file.BaseName -replace '\.agent$', '' }
      $fmEnd = $raw.IndexOf("`n---", 4)
      if ($fmEnd -lt 0) { return }
      $fm = $raw.Substring(0, $fmEnd)
      if ($fm -notmatch '(?m)^handoffs:') { return }

      foreach ($m in [regex]::Matches($fm, "(?m)^\s+-?\s*agent:\s*'?`"?([^'`"\r\n]+)")) {
        $target = $m.Groups[1].Value.Trim()

        if (-not $agentNames.ContainsKey($target)) {
          $errors += "agents/$($file.Name): handoff targets '$target', which is not the name of any agent — the button renders and does nothing, silently."
          continue
        }

        foreach ($pName in $profileAgentSets.Keys) {
          $set = $profileAgentSets[$pName]
          if ($set.ContainsKey($srcSlug) -and -not $set.ContainsKey($target)) {
            $warnings += "profile '$pName' ships agent '$srcSlug' but not its handoff target '$target' — that button is dead in projects using this profile"
          }
        }
      }
    }
  }
}

Write-Host "[lint] Checking always-loaded core file size ..."
# copilot-instructions.md is the only file loaded on EVERY turn, so it is the one place where drift
# is paid for continuously. 70 is a drift alarm, not a performance limit - the file is ~8% of what a
# .tsx edit loads, so ten lines cost nothing measurable. The point is that exceeding it should be a
# deliberate decision, not something noticed six months later. Enforced here rather than left as a
# comment because a limit nobody checks is a limit that only ratchets upward.
$coreMax = 70
$corePath = Join-Path $root 'copilot-instructions.template.md'
if (Test-Path -LiteralPath $corePath) {
  $coreLines = (Get-Content -LiteralPath $corePath).Count
  if ($coreLines -gt $coreMax) {
    $errors += "copilot-instructions.template.md: $coreLines lines, limit $coreMax. This file loads on every turn - move detail into instructions/ (glob-applied), docs/ (on-demand), or a prompt/agent/skill. If the limit itself is wrong, change it here and in QUICK_REFERENCE.md and README.md together."
  }
  elseif ($coreLines -gt ($coreMax - 5)) {
    $warnings += "copilot-instructions.template.md: $coreLines lines, limit $coreMax - approaching the cap, add nothing further without removing something"
  }
}

Write-Host "[lint] Checking hook script encoding ..."
# Hook scripts are launched by the Copilot host, which on Windows invokes Windows PowerShell 5.1.
# 5.1 decodes a BOM-less file as ANSI (cp1252), so a UTF-8 em-dash or emoji becomes mojibake -
# and the mojibake for U+2014 contains a double-quote, which TERMINATES any string it sits inside.
# Confirmed in a live session: every sessionStart and userPromptSubmitted hook died with
# "The string is missing the terminator". Keeping these scripts pure ASCII makes the cp1252 and
# UTF-8 decodings byte-identical, so the failure is structurally impossible rather than merely fixed.
Get-ChildItem -LiteralPath (Join-Path $root 'hooks/scripts') -File | ForEach-Object {
  $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  $start = if ($hasBom) { 3 } else { 0 }

  $high = 0
  for ($i = $start; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -gt 127) { $high++ } }
  if ($high -gt 0) {
    $errors += "hooks/scripts/$($_.Name): contains $high non-ASCII byte(s) - Windows PowerShell 5.1 reads BOM-less files as cp1252 and the mojibake breaks string terminators. Use ASCII tags like [OK]/[WARN] instead of emoji, '-' instead of em-dash."
  }

  if ($_.Extension -eq '.ps1' -and -not $hasBom) {
    $warnings += "hooks/scripts/$($_.Name): no UTF-8 BOM - harmless while the file is pure ASCII, but adds no protection if a non-ASCII character is introduced later"
  }
  # A BOM before #! stops the kernel recognising the shebang.
  if ($_.Extension -eq '.sh' -and $hasBom) {
    $errors += "hooks/scripts/$($_.Name): has a UTF-8 BOM before the shebang - the interpreter line will not be recognised"
  }
}

# sessionStart is the one event whose stdout is PARSED as JSON. A hook on that event must emit a
# single JSON object with `additionalContext`, or emit nothing at all.
#
# This is not a style rule. Observed 2026-08-01: `remind-memory.ps1` used Write-Host, and its plain
# text on stdout coincided with `dataverse-schema-drift` emitting a valid `additionalContext` that
# never reached the model - twice, with the drift hook's own log proving it had emitted. One
# malformed emitter appears to poison the whole batch, and the symptom is total silence from every
# other hook on the event, which is close to undiagnosable without this check.
$sessionStartScripts = @{}
Get-ChildItem -LiteralPath (Join-Path $root 'hooks') -Filter '*.json' -File | ForEach-Object {
  try { $cfg = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } catch { return }
  if (-not $cfg.hooks) { return }
  if ($cfg.hooks.PSObject.Properties.Name -notcontains 'sessionStart') { return }
  foreach ($entry in @($cfg.hooks.sessionStart)) {
    foreach ($key in @('powershell', 'bash')) {
      if ($entry.PSObject.Properties.Name -contains $key -and $entry.$key) {
        $sessionStartScripts[($entry.$key -replace '^\.github/', '')] = $_.Name
      }
    }
  }
}

foreach ($rel in $sessionStartScripts.Keys) {
  $path = Join-Path $root $rel
  if (-not (Test-Path -LiteralPath $path)) { continue }
  $body = Get-Content -LiteralPath $path -Raw

  # Strip comments so a line explaining the rule does not trip it.
  $code = ($body -split "`n" | Where-Object { $_.TrimStart() -notmatch '^\s*#' }) -join "`n"

  $offenders = @()
  if ($code -match '(?m)^\s*Write-Host\b')             { $offenders += 'Write-Host' }
  if ($code -match '(?m)^\s*echo\s+"')                 { $offenders += 'echo' }
  if ($code -match '(?m)^\s*Write-Output\s+"\[')       { $offenders += 'Write-Output of a bare string' }

  if ($offenders.Count -gt 0) {
    $errors += "$rel is a sessionStart hook ($($sessionStartScripts[$rel])) but writes plain text to stdout via $($offenders -join ', '). stdout is parsed as JSON on this event - emit @{ additionalContext = '...' } | ConvertTo-Json -Compress, or nothing. Non-JSON here silently suppresses additionalContext from every other sessionStart hook."
  }
}

# additionalContext must be emitted NESTED under hookSpecificOutput. The flat form is accepted,
# raises no error, and is silently discarded - so the hook logs success while the model sees nothing.
# Every context-injecting hook here had this bug and had never worked in any project; it cost a day
# of wrong conclusions about the platform before anyone read the spec.
# https://code.visualstudio.com/docs/agent-customization/hooks
Get-ChildItem -LiteralPath (Join-Path $root 'hooks/scripts') -File | ForEach-Object {
  $body = Get-Content -LiteralPath $_.FullName -Raw
  $code = ($body -split "`n" | Where-Object { $_.TrimStart() -notmatch '^\s*#' }) -join "`n"

  if ($body -notmatch 'additionalContext') { return }

  $flatPs  = $code -match '@\{\s*additionalContext\s*='
  $flatSh  = $code -match "'\{\s*additionalContext\s*:"
  if ($flatPs -or $flatSh) {
    $errors += "hooks/scripts/$($_.Name): emits a FLAT additionalContext. It must be nested - @{ hookSpecificOutput = @{ hookEventName = '<Event>'; additionalContext = `$msg } } - or the host discards it silently and the hook appears to work while reaching nobody."
  }

  # An emit swallowed into a comment is as silent as a wrongly-shaped one, and was introduced here by
  # a bulk edit whose replacement text lacked a trailing newline: the emit statement landed on the end
  # of a comment line, so two hooks ran, exited 0, logged success and produced nothing.
  #
  # Detect INTENT rather than the mere word: a commented line carrying both `additionalContext` and an
  # emit construct is a swallowed emit. A logger that only mentions the term in prose - explaining why
  # it must not write to stdout - is not, and must not be flagged.
  $swallowed = @($body -split "`n" | Where-Object {
    $_.TrimStart() -match '^\s*#' -and
    $_ -match 'additionalContext' -and
    ($_ -match 'ConvertTo-Json' -or $_ -match 'jq -n')
  })
  if ($swallowed.Count -gt 0) {
    $errors += "hooks/scripts/$($_.Name): an additionalContext emit is inside a comment line - the hook runs, exits 0 and outputs nothing. Put the emit on its own line."
  }
}

# Every .ps1 must also actually parse.
Get-ChildItem -LiteralPath (Join-Path $root 'hooks/scripts') -Filter '*.ps1' -File | ForEach-Object {
  $parseErrors = $null
  $tokens = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors)
  if ($parseErrors -and $parseErrors.Count -gt 0) {
    $errors += "hooks/scripts/$($_.Name): PowerShell parse error at line $($parseErrors[0].Extent.StartLineNumber) - $($parseErrors[0].Message)"
  }
}

Write-Host "[lint] Checking hook script runtime-safety patterns ..."
# These two cmdlets both throw under the Copilot host in ways that are fatal for a hook:
#   Add-Content : "Stream was not readable" when the host redirects the script's standard streams.
#   Join-Path   : DriveNotFoundException when the configured log dir is on a missing drive.
# Both scripts run with $ErrorActionPreference='Stop', so either throw exits non-zero - and a
# non-zero exit from a preToolUse hook BLOCKS THE TOOL CALL. A logging failure must never deny
# Copilot an operation. Observed live: tool-guardian blocking real tool calls on a log write.
Get-ChildItem -LiteralPath (Join-Path $root 'hooks/scripts') -Filter '*.ps1' -File | ForEach-Object {
  $raw = Get-Content -LiteralPath $_.FullName

  # Strip comments before matching, otherwise the explanatory comment inside the Write-HookLog
  # helper (which names the very cmdlets it exists to avoid) trips the check on every file.
  $code = ($raw | ForEach-Object {
    $line = $_
    $hash = $line.IndexOf('#')
    if ($hash -ge 0) { $line = $line.Substring(0, $hash) }
    $line
  }) -join "`n"

  if ($code -match 'Add-Content') {
    $errors += "hooks/scripts/$($_.Name): uses Add-Content - throws 'Stream was not readable' when the host redirects standard streams. Use the Write-HookLog helper ([System.IO.File]::AppendAllText inside try/catch)."
  }
  if ($code -match 'Join-Path') {
    $errors += "hooks/scripts/$($_.Name): uses Join-Path - resolves the PSDrive and throws DriveNotFoundException for a path on a missing drive. Use [System.IO.Path]::Combine()."
  }
  if ($code -match 'Write-HookLog' -and $code -notmatch 'function Write-HookLog') {
    $errors += "hooks/scripts/$($_.Name): calls Write-HookLog but does not define it. Hook scripts are invoked standalone, so the helper must be inlined, not dot-sourced."
  }

  # Two different ways a native command kills a hook script under $ErrorActionPreference = 'Stop',
  # one per PowerShell generation. Both were live bugs; both left NO log line, so the absence of a log
  # read as "the hook never fired" rather than "the hook crashed", and build-gate's type-error path
  # had never once worked.
  #
  #   PowerShell 7.3+ : a non-zero EXIT CODE becomes a terminating error.
  #                     Fixed by $PSNativeCommandUseErrorActionPreference = $false.
  #   Windows PS 5.1  : STDERR becomes a terminating ErrorRecord - no non-zero exit needed - and the
  #                     variable above does not exist there. THE COPILOT HOST USES 5.1.
  #
  # Redirection does NOT save you on 5.1. Verified 2026-07-27: `& git rev-parse ... 2>$null` outside a
  # repo still raised a terminating NativeCommandError - the redirect discards the stderr TEXT, but the
  # error record is raised regardless. So the only reliable fix is to genuinely lower the preference
  # around the call, which is what an inlined Invoke-NativeCommand wrapper does (and it must coerce
  # ErrorRecords to strings, or they re-throw when anything downstream touches them under 'Stop').
  # This rule found two latent instances the moment it was written: both scan-secrets and
  # check-licenses crashed on 5.1 whenever they ran OUTSIDE a git repo - i.e. the "skip gracefully,
  # this isn't a repo" path was the one path guaranteed to blow up.
  $setsStop = $code -match '(?m)^\s*\$ErrorActionPreference\s*=\s*[''"]Stop[''"]'
  $callsNative = $code -match '(?m)&\s*\$?(git|npx|npm|pnpm|yarn|node|dotnet|PM)\b'

  if ($setsStop -and $callsNative -and $code -notmatch 'PSNativeCommandUseErrorActionPreference') {
    $errors += "hooks/scripts/$($_.Name): invokes a native command under `$ErrorActionPreference='Stop' without setting `$PSNativeCommandUseErrorActionPreference = `$false. On PowerShell 7.3+ a non-zero exit code becomes a terminating error, so the script aborts before its own `$LASTEXITCODE check."
  }

  if ($setsStop -and $callsNative -and $code -notmatch 'function Invoke-NativeCommand') {
    $errors += "hooks/scripts/$($_.Name): invokes a native command under `$ErrorActionPreference='Stop' without an inlined Invoke-NativeCommand wrapper. Windows PowerShell 5.1 - which the Copilot host uses - turns native STDERR into a TERMINATING ErrorRecord even with 2>`$null, and `$PSNativeCommandUseErrorActionPreference does not exist there. The preference must be lowered around the call itself."
  }

  # Defining the wrapper is not the same as using it. An earlier version of this rule only checked
  # that Invoke-NativeCommand existed in the file, so scan-secrets.ps1 passed lint while seven bare
  # `& git` calls remained - and one of them died on a git WARNING (LF/CRLF, exit code 0, stderr
  # non-empty), which is exactly the case the wrapper exists to absorb. Checking for the presence of
  # a helper rather than its use is the same mistake as reviewing for the presence of code rather
  # than the presence of behaviour. Flag every bare invocation outside the wrapper body.
  if ($setsStop) {
    $lineNo = 0
    $inWrapper = $false
    foreach ($line in $raw) {
      $lineNo++
      if ($line -match 'function Invoke-NativeCommand') { $inWrapper = $true }
      elseif ($inWrapper -and $line -match '^\}') { $inWrapper = $false }
      if ($inWrapper) { continue }
      $stripped = $line -replace '#.*$', ''
      if ($stripped -match '&\s*\$?(git|npx|npm|pnpm|yarn|node|dotnet|PM)\b') {
        $errors += "hooks/scripts/$($_.Name):${lineNo}: bare native invocation under `$ErrorActionPreference='Stop' - route it through Invoke-NativeCommand. Even a zero-exit command that writes a WARNING to stderr (e.g. git's 'LF will be replaced by CRLF') raises a terminating ErrorRecord on Windows PowerShell 5.1."
      }
    }
  }
}

Write-Host "[lint] Checking GOVERNANCE_MATRIX.md is current ..."
$genScript = Join-Path $root 'tools/generate-governance-matrix.ps1'
if (Test-Path -LiteralPath $genScript) {
  & pwsh -NoProfile -File $genScript -Check *> $null
  if ($LASTEXITCODE -ne 0) {
    $errors += "GOVERNANCE_MATRIX.md is out of date — run: pwsh ./tools/generate-governance-matrix.ps1"
  }
}

Write-Host ""
if ($warnings.Count -gt 0) {
  Write-Host "=== WARNINGS ($($warnings.Count)) ===" -ForegroundColor Yellow
  $warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
if ($errors.Count -gt 0) {
  Write-Host "=== ERRORS ($($errors.Count)) ===" -ForegroundColor Red
  $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  Write-Host ""
  Write-Host "[lint] FAILED — $($errors.Count) error(s), $($warnings.Count) warning(s)" -ForegroundColor Red
  exit 1
}

Write-Host "[lint] PASSED — 0 errors, $($warnings.Count) warning(s)" -ForegroundColor Green
exit 0
