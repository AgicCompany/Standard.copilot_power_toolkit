#Requires -Version 5.1
<#
.SYNOPSIS
  Project Context Check Hook (PowerShell) - mirrors check-project-context.sh exactly; keep both in sync.
.DESCRIPTION
  Event: sessionStart. stdout IS PARSED for this event - emit one JSON object with
  `additionalContext`, or emit nothing. Never Write-Host, never echo a status line: on a parsed event
  one malformed emitter appears to poison the whole batch, so other hooks' context is lost too.

  WHY THIS EXISTS. `project-context.md` ships as a template that someone is supposed to fill in by
  running `/setup`. Across an entire 11-step acceptance run in two projects, nobody ever did - the
  mechanism existed, worked, and was documented, and nothing in the flow caused anyone to invoke it.

  An unfilled template is worse than an absent file. Observed live 2026-08-02: an agent spent a step
  reading it and concluding "I'm skipping the project context file since it's just a template and I
  can't verify the details". It is loaded early, it is noise, and it has to be routed around on every
  task until someone fills it.

  Wording is deliberately a GATE, not an advisory. Measured A/B on this baseline's own hooks: "offer
  to..." and "raise it once" were read, deprioritised, and acted on only when challenged; "STOP - ACT
  ON THIS BEFORE..." produced compliance. The escape hatch below is what prevents nagging, NOT softer
  language.
.NOTES
  Env vars: SKIP_PROJECT_CONTEXT_CHECK (true to disable),
            PROJECT_CONTEXT_FILE (default .github/project-context.md)
#>

$ErrorActionPreference = 'Stop'

if ($env:SKIP_PROJECT_CONTEXT_CHECK -eq 'true') { exit 0 }

$ContextFile = if ($env:PROJECT_CONTEXT_FILE) { $env:PROJECT_CONTEXT_FILE } else { '.github/project-context.md' }

# No file at all is fine - a project that never copied the template does not need telling every
# session. This hook fires only for the specific failure it exists to catch: the file is PRESENT and
# still unfilled.
if (-not (Test-Path -LiteralPath $ContextFile)) { exit 0 }

# Template tells: the italic placeholder hints, and the instruction header from the template itself.
# Matching on placeholders rather than on absence of content is what keeps this quiet once the file
# is real - a filled file has no `*e.g. ...*` lines left.
$patterns = @(
  '\*e\.g\.',
  'Fill this file after copying',
  'Delete the italic hint text'
)

$hits = 0
foreach ($pattern in $patterns) {
  $found = Select-String -LiteralPath $ContextFile -Pattern $pattern -ErrorAction SilentlyContinue
  if ($found) { $hits += @($found).Count }
}

if ($hits -eq 0) { exit 0 }

$msg = @"
STOP - ACT ON THIS BEFORE YOUR FIRST EDIT. This is a gate, not background information.

'$ContextFile' is still the unfilled template ($hits placeholder line(s) remain). Until it is filled, it is not neutral - it is noise you have to route around on every task, and it will be read by later sessions as if it were fact.

Raise this in your FIRST reply, before any of the work: tell the user the file is unfilled and offer to run the '/setup' prompt, which fills it from what is actually in the repo. Telling them afterwards is worthless - the point is to fix it before it shapes anything else.

Do NOT fill it in from assumption. Every line must trace to a file you have read: package.json for versions, power.config.json for environment and data sources, the feature code itself for how something is implemented. Ask about anything you cannot verify; 'none yet' is a good answer, a plausible guess is not.

If the user says the file is deliberately unfilled, accept that and do not raise it again this session.
"@

# Payload MUST be nested under hookSpecificOutput with hookEventName. A flat { additionalContext } is
# accepted, errors nothing, and is silently discarded.
# Spec: https://code.visualstudio.com/docs/agent-customization/hooks
@{
  hookSpecificOutput = @{
    hookEventName     = 'SessionStart'
    additionalContext = $msg
  }
} | ConvertTo-Json -Compress -Depth 4
exit 0
