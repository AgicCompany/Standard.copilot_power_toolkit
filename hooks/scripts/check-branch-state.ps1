#Requires -Version 5.1
<#
.SYNOPSIS
  Protected Branch Guard Hook (PowerShell) - mirrors check-branch-state.sh exactly; keep both in sync.
.DESCRIPTION
  Event: sessionStart. stdout IS parsed for this event - `additionalContext` is injected into the
  session, which is how the warning reaches Copilot. `userPromptSubmitted` stdout is IGNORED, so a
  per-prompt version of this check is not possible - see docs/reference/hook-payloads.md.

  Gitflow says branch first, then work. Nothing enforced that: copilot-instructions.md can make the
  model REFUSE to commit to main (verified), but nothing tells anyone they are already sitting on it
  with uncommitted changes. By then the work is on the wrong branch and someone has to untangle it.
  This is mechanically checkable, so it is a hook rather than prose.
.NOTES
  Env vars: SKIP_BRANCH_GUARD (true to disable),
            PROTECTED_BRANCHES (comma-separated, default 'main,master,develop')
#>

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# Windows PowerShell 5.1 - which the Copilot host uses - turns a native command's STDERR into a
# TERMINATING ErrorRecord under 'Stop', even with 2>$null and even on exit code 0 (git's
# "LF will be replaced by CRLF" warning is the case that caught this). The preference has to be
# lowered around the call itself. See docs/reference/hook-payloads.md.
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

if ($env:SKIP_BRANCH_GUARD -eq 'true') { exit 0 }

$repo = Invoke-NativeCommand -Command 'git' -Arguments @('rev-parse', '--is-inside-work-tree')
if ($repo.ExitCode -ne 0) { exit 0 }

$branchResult = Invoke-NativeCommand -Command 'git' -Arguments @('branch', '--show-current')
$branch = ($branchResult.Output | Select-Object -First 1)
if ($branch) { $branch = $branch.Trim() }
# Detached HEAD, or a repo with no commits yet - nothing useful to say either way.
if ([string]::IsNullOrWhiteSpace($branch)) { exit 0 }

$protectedList = if ($env:PROTECTED_BRANCHES) { $env:PROTECTED_BRANCHES } else { 'main,master,develop' }
$protected = @($protectedList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($protected -notcontains $branch) { exit 0 }

$statusResult = Invoke-NativeCommand -Command 'git' -Arguments @('status', '--porcelain')
$changed = @($statusResult.Output | Where-Object { $_ -and $_.Trim() })

# On a protected branch with a clean tree is the NORMAL state at the start of work - saying anything
# here would fire on every session in every repo and train people to ignore it. Only speak when there
# is uncommitted work, which is the state that actually costs something to unwind.
if ($changed.Count -eq 0) { exit 0 }

$sample = ($changed | Select-Object -First 5 | ForEach-Object { "  $_" }) -join "`n"
$more = if ($changed.Count -gt 5) { "`n  ... and $($changed.Count - 5) more" } else { '' }

$msg = @"
STOP - ACT ON THIS BEFORE YOUR FIRST EDIT. This is a gate, not background information.

You are on '$branch', a protected branch, with $($changed.Count) uncommitted change(s):

$sample$more

DO NOT create, edit or delete any file until you have raised this with the user AND THEY HAVE
ANSWERED. Raise it in your FIRST reply, before doing any of the work you were asked to do - telling
them afterwards is worthless, because the files are already on the protected branch by then.

**Asking and then proceeding in the same turn is not compliance.** End the turn after asking. Reading
files to plan is fine; writing is not. "I asked, got no reply, so I went ahead and noted it
afterwards" is the specific failure this exists to prevent - it produces exactly the outcome the gate
was meant to stop, plus the appearance of having followed it. If the user has already answered this
session, honour that answer and do not ask again.

Say: this repo branches BEFORE work starts (Gitflow - feature/* and release/* from 'develop',
hotfix/* from 'main'), you are on '$branch' with uncommitted work, and moving it later costs more
than moving it now. Then offer: 'git stash', create 'feature/<issue-id>-short-description', 'git
stash pop'. Never commit first - that puts a commit on the protected branch, which is the thing
being avoided. The 'delivery' agent does this.

If the user says the changes are deliberate and staying put, accept that, proceed, and do not raise
it again this session. Answering the request first and mentioning this afterwards is the one
outcome that is not acceptable.
"@

# Payload MUST be nested under hookSpecificOutput with hookEventName. A flat
# { additionalContext } is accepted, errors nothing, and is silently discarded.
# Spec: https://code.visualstudio.com/docs/agent-customization/hooks
@{
  hookSpecificOutput = @{
    hookEventName     = 'SessionStart'
    additionalContext = $msg
  }
} | ConvertTo-Json -Compress -Depth 4
exit 0
