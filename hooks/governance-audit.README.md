---
name: 'Governance Audit'
description: 'Scans Copilot agent prompts for threat signals and logs governance events'
tags: ['security', 'governance', 'audit', 'safety']
---

# Governance Audit Hook

Real-time threat detection and audit logging for GitHub Copilot coding agent sessions. Scans user
prompts for dangerous patterns before the agent processes them.

## Overview

This hook provides governance controls for Copilot coding agent sessions:
- **Threat detection**: Scans prompts for data exfiltration, privilege escalation, system destruction, prompt injection, and credential exposure
- **Governance levels**: Open, standard, strict, locked — from audit-only to full blocking
- **Audit trail**: Append-only JSON log of all governance events
- **Session summary**: Reports threat counts at session end

## Threat Categories

| Category | Examples | Severity |
|----------|----------|----------|
| `data_exfiltration` | "send all records to external API" | 0.7 - 0.95 |
| `privilege_escalation` | "sudo", "chmod 777", "add to sudoers" | 0.8 - 0.95 |
| `system_destruction` | "rm -rf /", "drop database" | 0.9 - 0.95 |
| `prompt_injection` | "ignore previous instructions" | 0.6 - 0.9 |
| `credential_exposure` | Hardcoded API keys, AWS access keys | 0.9 - 0.95 |

## Governance Levels

| Level | Behavior |
|-------|----------|
| `open` | Log threats only, never block |
| `standard` | Log threats, block only if `BLOCK_ON_THREAT=true` |
| `strict` | Log and block all detected threats |
| `locked` | Log and block all detected threats |

## Installation

Part of the `.github_general` baseline — `tools/apply-baseline.ps1` copies `governance-audit.json`
and `scripts/audit-session-start.{sh,ps1}`, `audit-session-end.{sh,ps1}`, `audit-prompt.{sh,ps1}`
into your project automatically. To install standalone:

```bash
cp governance-audit.json your-repo/.github/hooks/
cp scripts/audit-*.sh scripts/audit-*.ps1 your-repo/.github/hooks/scripts/
chmod +x your-repo/.github/hooks/scripts/audit-*.sh
mkdir -p logs/copilot/governance
```

## Configuration

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `GOVERNANCE_LEVEL` | `open`, `standard`, `strict`, `locked` | `standard` | Controls blocking behavior |
| `BLOCK_ON_THREAT` | `true`, `false` | `false` | Block prompts with threats (standard level) |
| `SKIP_GOVERNANCE_AUDIT` | `true` | unset | Disable governance audit entirely |

## Log Format

Events are written to `logs/copilot/governance/audit.log` in JSON Lines format:

```json
{"timestamp":"2026-01-15T10:30:00Z","event":"session_start","governance_level":"standard","cwd":"/workspace/project"}
{"timestamp":"2026-01-15T10:31:00Z","event":"prompt_scanned","governance_level":"standard","status":"clean"}
{"timestamp":"2026-01-15T10:32:00Z","event":"threat_detected","governance_level":"standard","threat_count":1,"threats":[{"category":"privilege_escalation","severity":0.8,"description":"Elevated privileges","evidence":"sudo"}]}
{"timestamp":"2026-01-15T10:45:00Z","event":"session_end","total_events":12,"threats_detected":1}
```

## Privacy & Security

- Full prompts are **never** logged — only matched threat patterns (minimal evidence snippets) and metadata are recorded.
  A `credential_exposure` match *is* the secret, so its evidence is redacted to the first and last 4 characters
  (or `[REDACTED]`), the same rule `secrets-scanner` uses
- `logs/copilot/.gitignore` is created automatically on first run, so logs stay out of git — delete it only if you deliberately want to commit them
- Set `SKIP_GOVERNANCE_AUDIT=true` to disable entirely
- All data stays local — no external network calls
