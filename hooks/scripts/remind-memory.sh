#!/usr/bin/env bash
#
# Memory Reminder Hook (bash) - mirrors remind-memory.ps1 exactly; keep both in sync.
#
# Event: sessionStart. stdout IS PARSED for this event - it must be a single JSON object or nothing.
#
# This script used to `echo` a plain-text reminder. That did more than waste the message: on a parsed
# event, one malformed emitter appears to poison the whole batch, so the valid `additionalContext`
# from OTHER sessionStart hooks never reached the model either. Diagnosed 2026-08-01 -
# `dataverse-schema-drift` logged `emitted_drift_warning` while Copilot showed no sign of it, twice,
# until this script was found writing plain text alongside it.
#
# Rule for every sessionStart hook: emit one JSON object with `additionalContext`, or emit nothing.
# Never echo a status line.
#
# Environment variables:
#   SKIP_MEMORY_REMINDER - "true" to disable entirely (default: unset)
#   MEMORY_FILE          - Path to the memory file (default: .github/docs/project-memory.md)

set -uo pipefail

if [[ "${SKIP_MEMORY_REMINDER:-}" == "true" ]]; then
  exit 0
fi

MEMORY_FILE="${MEMORY_FILE:-.github/docs/project-memory.md}"

# Silent by design when there is nothing to say. A brand-new project has no memory file and does not
# need telling on every session start - noise in injected context is not free.
[[ -f "$MEMORY_FILE" ]] || exit 0

# jq is how this script emits JSON; without it, stay silent rather than echo raw text.
command -v jq >/dev/null 2>&1 || exit 0

# `|| ENTRY_COUNT=0`, never `|| echo 0`: grep -c PRINTS "0" and EXITS 1 when there are no matches, so
# the echo appends a second line and this becomes "0\n0". The numeric test then errors, the script
# falls through, and a project with an empty memory file gets a reminder claiming it has entries.
# Same bug found in check-project-context.sh by tools/probe-hooks.sh on 2026-08-03; this one had been
# shipping and running every session.
ENTRY_COUNT=$(grep -cE '^\s*-\s+[0-9]{4}-[0-9]{2}-[0-9]{2}:' "$MEMORY_FILE" 2>/dev/null) || ENTRY_COUNT=0
[[ -z "$ENTRY_COUNT" ]] && ENTRY_COUNT=0
[[ "$ENTRY_COUNT" -eq 0 ]] && exit 0

if [[ "$ENTRY_COUNT" -eq 1 ]]; then PLURAL="y"; else PLURAL="ies"; fi
MSG="Project memory: '$MEMORY_FILE' has $ENTRY_COUNT recorded entr${PLURAL}. Read it before non-trivial work - it holds decisions and constraints for this project that are not derivable from the code."

jq -n --arg ctx "$MSG" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
