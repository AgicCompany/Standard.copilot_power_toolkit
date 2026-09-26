#!/usr/bin/env bash
#
# Project Context Check Hook (bash) - mirrors check-project-context.ps1 exactly; keep both in sync.
#
# Event: sessionStart. stdout IS PARSED for this event - emit one JSON object with
# `additionalContext`, or emit nothing. Never echo a status line: on a parsed event one malformed
# emitter appears to poison the whole batch, so other hooks' context is lost too.
#
# WHY THIS EXISTS. `project-context.md` ships as a template that someone is supposed to fill in by
# running `/setup`. Across an entire 11-step acceptance run in two projects, nobody ever did - the
# mechanism existed, worked, and was documented, and nothing in the flow caused anyone to invoke it.
#
# An unfilled template is worse than an absent file. Observed live 2026-08-02: an agent spent a step
# reading it and concluding "I'm skipping the project context file since it's just a template and I
# can't verify the details". It is loaded early, it is noise, and it has to be routed around on every
# task until someone fills it.
#
# Wording is deliberately a GATE, not an advisory. Measured A/B on this baseline's own hooks:
# "offer to..." and "raise it once" were read, deprioritised, and acted on only when challenged;
# "STOP - ACT ON THIS BEFORE..." produced compliance. The escape hatch in the message is what
# prevents nagging, NOT softer language.
#
# Environment variables:
#   SKIP_PROJECT_CONTEXT_CHECK - "true" to disable entirely (default: unset)
#   PROJECT_CONTEXT_FILE       - Path to the file (default: .github/project-context.md)

set -uo pipefail

if [[ "${SKIP_PROJECT_CONTEXT_CHECK:-}" == "true" ]]; then
  exit 0
fi

CONTEXT_FILE="${PROJECT_CONTEXT_FILE:-.github/project-context.md}"

# No file at all is fine - a project that never copied the template does not need telling every
# session. This hook fires only for the specific failure it exists to catch: PRESENT and unfilled.
[[ -f "$CONTEXT_FILE" ]] || exit 0

# jq is how this script emits JSON; without it, stay silent rather than echo raw text.
command -v jq >/dev/null 2>&1 || exit 0

# Template tells: the italic placeholder hints and the template's own instruction header. Matching on
# placeholders rather than on absence of content is what keeps this quiet once the file is real - a
# filled file has no `*e.g. ...*` lines left.
# `|| HITS=0`, never `|| echo 0`: grep -c PRINTS "0" and EXITS 1 when there are no matches, so the
# echo appends a second line and $HITS becomes "0\n0". The numeric test below then errors, the script
# falls through, and the hook speaks on a file that is perfectly fine. Caught 2026-08-03 by the first
# CI run of tools/probe-hooks.sh - both the "filled file" and "empty file" cases.
HITS=$(grep -cE '\*e\.g\.|Fill this file after copying|Delete the italic hint text' "$CONTEXT_FILE" 2>/dev/null) || HITS=0
[[ -z "$HITS" ]] && HITS=0
[[ "$HITS" -eq 0 ]] && exit 0

if [[ "$HITS" -eq 1 ]]; then LINE_WORD="line"; else LINE_WORD="lines"; fi

MSG="STOP - ACT ON THIS BEFORE YOUR FIRST EDIT. This is a gate, not background information.

'$CONTEXT_FILE' is still the unfilled template ($HITS placeholder $LINE_WORD remain). Until it is filled, it is not neutral - it is noise you have to route around on every task, and it will be read by later sessions as if it were fact.

Raise this in your FIRST reply, before any of the work: tell the user the file is unfilled and offer to run the '/setup' prompt, which fills it from what is actually in the repo. Telling them afterwards is worthless - the point is to fix it before it shapes anything else.

Do NOT fill it in from assumption. Every line must trace to a file you have read: package.json for versions, power.config.json for environment and data sources, the feature code itself for how something is implemented. Ask about anything you cannot verify; 'none yet' is a good answer, a plausible guess is not.

If the user says the file is deliberately unfilled, accept that and do not raise it again this session."

jq -n --arg ctx "$MSG" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
