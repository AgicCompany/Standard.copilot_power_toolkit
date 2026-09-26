#!/bin/bash

# Log session end event

set -euo pipefail

# Skip if logging disabled
if [[ "${SKIP_LOGGING:-}" == "true" ]]; then
  exit 0
fi

# Read input from Copilot
INPUT=$(cat)

# This script is registered on BOTH 'sessionEnd' and 'Stop' (see session-logger.json), so a
# hardcoded label made every Stop firing read as 'sessionEnd' in the log. That is worse than an
# unlabelled entry: sessionEnd is probe-verified to NEVER fire in VS Code Copilot Chat, and the
# mislabelled log later convinced an audit that it did - contradicting a correct finding on the
# strength of the script's own bad bookkeeping. Take the name from the payload the host sent.
EVENT_NAME=$(printf '%s' "$INPUT" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
if [[ -z "$EVENT_NAME" ]]; then
  EVENT_NAME=$(printf '%s' "$INPUT" | sed -n 's/.*"hookEventName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi
[[ -z "$EVENT_NAME" ]] && EVENT_NAME="unknown"

# Create logs directory if it doesn't exist
mkdir -p logs/copilot

# Extract timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "{\"timestamp\":\"$TIMESTAMP\",\"event\":\"$EVENT_NAME\"}" >> logs/copilot/session.log

echo "[LOG] $EVENT_NAME logged"
exit 0
