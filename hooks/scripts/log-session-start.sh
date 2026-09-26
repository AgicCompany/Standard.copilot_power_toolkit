#!/bin/bash

# Log session start event

set -euo pipefail

# Skip if logging disabled
if [[ "${SKIP_LOGGING:-}" == "true" ]]; then
  exit 0
fi

# Read input from Copilot
INPUT=$(cat)

# Create logs directory if it doesn't exist
mkdir -p logs/copilot

# logs/ is not in a project's .gitignore by default, and these files hold prompt fragments, file
# paths and commands. Make the folder ignore itself: it never edits the project's own .gitignore and
# works however the baseline was installed. Delete logs/copilot/.gitignore to commit logs on purpose.
if [[ ! -f logs/copilot/.gitignore ]]; then
  printf '%s
' '# Created by the Copilot baseline hooks. These logs can hold prompt fragments,'     '# file paths and commands - they are not for version control. Delete this file only'     '# if you deliberately want to commit them.' '*' > logs/copilot/.gitignore 2>/dev/null || true
fi

# Extract timestamp and session info
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CWD=$(pwd)

# Log session start (use jq for proper JSON encoding)
jq -Rn --arg timestamp "$TIMESTAMP" --arg cwd "$CWD" '{"timestamp":$timestamp,"event":"sessionStart","cwd":$cwd}' >> logs/copilot/session.log

# stdout is PARSED as JSON on sessionStart. A status line here silently suppresses additionalContext
# from EVERY other sessionStart hook. The real record goes to the log file above.
exit 0
