---
name: 'Session Logger'
description: 'Logs all Copilot coding agent session activity for audit and analysis'
tags: ['logging', 'audit', 'analytics']
---

# Session Logger Hook

Comprehensive logging for GitHub Copilot coding agent sessions, tracking session starts, ends, and
user prompts for audit trails and usage analytics.

## Overview

This hook provides detailed logging of Copilot coding agent activity:
- Session start/end times with working directory context
- User prompt submission events
- Configurable log levels

## Installation

Part of the `.github_general` baseline — `tools/apply-baseline.ps1` copies `session-logger.json` and
`scripts/log-session-start.{sh,ps1}`, `log-session-end.{sh,ps1}`, `log-prompt.{sh,ps1}` into your
project automatically. To install standalone:

```bash
cp session-logger.json your-repo/.github/hooks/
cp scripts/log-session-start.sh scripts/log-session-start.ps1 \
   scripts/log-session-end.sh scripts/log-session-end.ps1 \
   scripts/log-prompt.sh scripts/log-prompt.ps1 \
   your-repo/.github/hooks/scripts/
chmod +x your-repo/.github/hooks/scripts/log-*.sh
```

## Configuration

| Variable | Values | Default | Description |
|---|---|---|---|
| `SKIP_LOGGING` | `true` | unset | Disable logging entirely |
| `LOG_LEVEL` | any string | `INFO` | Tagged onto `userPromptSubmitted` log lines |

## Log Format

Session events are written to `logs/copilot/session.log` and prompt events to
`logs/copilot/prompts.log` in JSON Lines format:

```json
{"timestamp":"2026-01-15T10:30:00Z","event":"sessionStart","cwd":"/workspace/project"}
{"timestamp":"2026-01-15T10:35:00Z","event":"sessionEnd"}
```

## Privacy & Security

- Add `logs/` to `.gitignore` to avoid committing session data
- Set `SKIP_LOGGING=true` to disable
- Logs are stored locally only
