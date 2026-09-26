---
name: 'Session Logger'
description: 'Logs metadata when Copilot sessions start, each turn completes, and a prompt is submitted - timestamps, working directory and event names; no prompt text and no tool calls'
tags: ['logging', 'audit', 'analytics']
---

# Session Logger Hook

Lightweight metadata logging for Copilot sessions: when they start, when each turn completes, and
when a prompt is submitted. Useful for usage timelines, not as an audit of what an agent did.

## Overview

What it records, and nothing more:

| Event | Log line |
|---|---|
| Session start | timestamp, working directory |
| Each completed turn (`Stop`) | timestamp, event name |
| Prompt submitted | timestamp, event name, `LOG_LEVEL` label — **not the prompt text** |

It does **not** log tool calls, tool arguments, or anything the model wrote. Do not rely on it as an
audit of what an agent *did* — for that, see the logs written by `tool-guardian` and
`governance-audit`.

`sessionEnd` is registered too, but in VS Code Copilot Chat it never fires (see
`docs/reference/hook-payloads.md`); `Stop` is what records turn completion.

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

- `logs/copilot/.gitignore` is created automatically on first run, so logs stay out of git — delete it only if you deliberately want to commit them
- Set `SKIP_LOGGING=true` to disable
- Logs are stored locally only
