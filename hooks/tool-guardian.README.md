---
name: 'Tool Guardian'
description: 'Blocks dangerous tool operations (destructive file ops, force pushes, DB drops) before the Copilot coding agent executes them'
tags: ['security', 'safety', 'preToolUse', 'guardrails']
---

# Tool Guardian Hook

Blocks dangerous tool operations before a GitHub Copilot coding agent executes them, acting as a
safety net against destructive commands, force pushes, database drops, and other high-risk actions.

## Overview

AI coding agents can autonomously execute shell commands, file operations, and database queries.
Without guardrails, a misinterpreted instruction could lead to irreversible damage. This hook
intercepts every tool invocation at the `preToolUse` event and scans it against ~20 threat patterns
across 6 categories:

- **Destructive file ops**: `rm -rf /`, deleting `.env` or `.git`
- **Destructive git ops**: `git push --force` to main/master, `git reset --hard`
- **Database destruction**: `DROP TABLE`, `DROP DATABASE`, `TRUNCATE`, `DELETE FROM` without `WHERE`
- **Permission abuse**: `chmod 777`, recursive world-writable permissions
- **Network exfiltration**: `curl | bash`, `wget | sh`, uploading files via `curl --data @`
- **System danger**: `sudo`, `npm publish`

## Features

- **Two guard modes**: `block` (exit non-zero to prevent execution) or `warn` (log only)
- **Safer alternatives**: Every blocked pattern includes a suggestion for a safer command
- **Allowlist support**: Skip specific patterns via `TOOL_GUARD_ALLOWLIST`
- **Structured logging**: JSON Lines output for integration with monitoring tools
- **Fast execution**: 10-second timeout; no external network calls
- **Cross-platform**: bash and PowerShell implementations, same behavior

## Installation

Part of the `.github_general` baseline — `tools/apply-baseline.ps1` copies `tool-guardian.json` and
`scripts/guard-tool.{sh,ps1}` into your project automatically. To install standalone:

```bash
cp tool-guardian.json your-repo/.github/hooks/
cp scripts/guard-tool.sh scripts/guard-tool.ps1 your-repo/.github/hooks/scripts/
chmod +x your-repo/.github/hooks/scripts/guard-tool.sh
mkdir -p logs/copilot/tool-guardian && echo "logs/" >> .gitignore
```

## Configuration

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `GUARD_MODE` | `warn`, `block` | `block` | `warn` logs threats only; `block` exits non-zero to prevent tool execution |
| `SKIP_TOOL_GUARD` | `true` | unset | Disable the guardian entirely |
| `TOOL_GUARD_LOG_DIR` | path | `logs/copilot/tool-guardian` | Directory where guard logs are written |
| `TOOL_GUARD_ALLOWLIST` | comma-separated | unset | Patterns to skip (e.g., `git push --force,npm publish`) |

## How It Works

1. Before the Copilot coding agent executes a tool, the hook receives the tool invocation as JSON on stdin
2. Extracts `toolName`, and `toolArgs` — **`toolArgs` is itself a JSON string** (per the authoritative
   hooks payload schema), so it's parsed a second time and all its values (`command`, `path`,
   `description`, whatever the tool provides) are flattened into one string for pattern matching.
   An earlier version of this hook read a `toolInput` field that doesn't exist in the real payload,
   meaning it was effectively blind to actual command content the whole time — confirmed and fixed.
3. Checks the combined text against the allowlist — if matched, skips all scanning
4. Scans combined text against ~20 regex threat patterns across 6 severity categories
5. Reports findings with category, severity, matched text, and a safer alternative
6. Writes a structured JSON log entry for audit purposes
7. In `block` mode, exits non-zero to prevent the tool from executing
8. In `warn` mode, logs the threat and allows execution to proceed

## Threat Categories

| Category | Severity | Key Patterns | Suggestion |
|----------|----------|-------------|------------|
| `destructive_file_ops` | critical | `rm -rf /`, `rm -rf ~`, `rm -rf .`, delete `.env`/`.git` | Use targeted paths or `mv` to back up |
| `destructive_git_ops` | critical/high | `git push --force` to main/master, `git reset --hard`, `git clean -fd` | Use `--force-with-lease`, `git stash`, dry-run |
| `database_destruction` | critical/high | `DROP TABLE`, `DROP DATABASE`, `TRUNCATE`, `DELETE FROM` without WHERE | Use migrations, backups, add WHERE clause |
| `permission_abuse` | high | `chmod 777`, `chmod -R 777` | Use `755` for dirs, `644` for files |
| `network_exfiltration` | critical/high | `curl \| bash`, `wget \| sh`, `curl --data @file` | Download first, review, then execute |
| `system_danger` | high | `sudo`, `npm publish` | Use least privilege; `--dry-run` first |

## Examples

### Safe command (exit 0)

```bash
echo '{"toolName":"bash","toolArgs":"{\"command\":\"git status\"}"}' | bash scripts/guard-tool.sh
```

### Blocked command (exit 1)

```bash
echo '{"toolName":"bash","toolArgs":"{\"command\":\"git push --force origin main\"}"}' | \
  GUARD_MODE=block bash scripts/guard-tool.sh
```

```
🛡️  Tool Guardian: 1 threat(s) detected in 'bash' invocation

  CATEGORY                 SEVERITY   MATCH                                    SUGGESTION
  --------                 --------   -----                                    ----------
  destructive_git_ops      critical   git push --force origin main             Use 'git push --force-with-lease' or push to a feature branch

🚫 Operation blocked: resolve the threats above or adjust TOOL_GUARD_ALLOWLIST.
   Set GUARD_MODE=warn to log without blocking.
```

## Log Format

Guard events are written to `logs/copilot/tool-guardian/guard.log` in JSON Lines format:

```json
{"timestamp":"2026-03-16T10:30:00Z","event":"threats_detected","mode":"block","tool":"bash","threat_count":1,"threats":[{"category":"destructive_git_ops","severity":"critical","match":"git push --force origin main","suggestion":"Use 'git push --force-with-lease' or push to a feature branch"}]}
```

## Customization

- **Add custom patterns**: Edit the `$Patterns` array in `scripts/guard-tool.ps1` (and mirror in `.sh`)
- **Allowlist known commands**: Use `TOOL_GUARD_ALLOWLIST` for commands that are safe in your context
- **Change log location**: Set `TOOL_GUARD_LOG_DIR` to route logs to your preferred directory

## Disabling

Set `SKIP_TOOL_GUARD=true`, or remove the `preToolUse` entry from `tool-guardian.json`.

## Limitations

- Pattern-based detection; does not perform semantic analysis of command intent
- May produce false positives for commands that match patterns in safe contexts (use the allowlist)
- Scans the text representation of tool args; cannot detect obfuscated or encoded commands
