#!/bin/bash

# Governance Audit: Log session start with governance context

set -euo pipefail

if [[ "${SKIP_GOVERNANCE_AUDIT:-}" == "true" ]]; then
  exit 0
fi

INPUT=$(cat)

mkdir -p logs/copilot/governance

# logs/ is not in a project's .gitignore by default, and these files hold prompt fragments, file
# paths and commands. Make the folder ignore itself: it never edits the project's own .gitignore and
# works however the baseline was installed. Delete logs/copilot/.gitignore to commit logs on purpose.
if [[ ! -f logs/copilot/.gitignore ]]; then
  printf '%s
' '# Created by the Copilot baseline hooks. These logs can hold prompt fragments,'     '# file paths and commands - they are not for version control. Delete this file only'     '# if you deliberately want to commit them.' '*' > logs/copilot/.gitignore 2>/dev/null || true
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CWD=$(pwd)
LEVEL="${GOVERNANCE_LEVEL:-standard}"

# Without jq, write a reduced line rather than fail: under `set -e` a missing jq exited 127 and the
# hook errored on every session. Hand-built JSON, so only sanitised values; cwd is left out.
if command -v jq >/dev/null 2>&1; then
  jq -Rn \
    --arg timestamp "$TIMESTAMP" \
    --arg cwd "$CWD" \
    --arg level "$LEVEL" \
    '{"timestamp":$timestamp,"event":"session_start","governance_level":$level,"cwd":$cwd}' \
    >> logs/copilot/governance/audit.log
else
  SAFE_LEVEL="$(printf '%s' "$LEVEL" | tr -cd 'A-Za-z0-9_-')"
  printf '{"timestamp":"%s","event":"session_start","governance_level":"%s","log":"reduced-no-jq"}\n' \
    "$TIMESTAMP" "$SAFE_LEVEL" >> logs/copilot/governance/audit.log
fi

# stdout is PARSED as JSON on sessionStart. A status line here silently suppresses additionalContext
# from EVERY other sessionStart hook. The real record goes to the log file above.
exit 0
