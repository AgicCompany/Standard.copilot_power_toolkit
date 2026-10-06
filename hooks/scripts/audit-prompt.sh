#!/bin/bash

# Governance Audit: Scan user prompts for threat signals before agent processing
#
# Environment variables:
#   GOVERNANCE_LEVEL - "open", "standard", "strict", "locked" (default: standard)
#   BLOCK_ON_THREAT  - "true" to exit non-zero on threats (default: false)
#   SKIP_GOVERNANCE_AUDIT - "true" to disable (default: unset)

set -euo pipefail

if [[ "${SKIP_GOVERNANCE_AUDIT:-}" == "true" ]]; then
  exit 0
fi

INPUT=$(cat)

# jq is used ONLY to write the rich log lines. Detection (grep) and the blocking policy do not need
# it, and must not depend on it: an early `exit 0` here once made strict/locked mode silently accept
# every prompt on a machine without jq. So without jq, detect and enforce as normal and write a
# reduced log line with printf instead.
HAVE_JQ=0
if command -v jq &>/dev/null; then
  HAVE_JQ=1
else
  echo "[WARN] governance-audit: jq not found - prompts are still screened and policy still enforced, but the audit log is reduced. Install jq (required on macOS/Linux)." >&2
fi

mkdir -p logs/copilot/governance

# logs/ is not in a project's .gitignore by default, and these files hold prompt fragments, file
# paths and commands. Make the folder ignore itself: it never edits the project's own .gitignore and
# works however the baseline was installed. Delete logs/copilot/.gitignore to commit logs on purpose.
if [[ ! -f logs/copilot/.gitignore ]]; then
  printf '%s
' '# Created by the Copilot baseline hooks. These logs can hold prompt fragments,'     '# file paths and commands - they are not for version control. Delete this file only'     '# if you deliberately want to commit them.' '*' > logs/copilot/.gitignore 2>/dev/null || true
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LEVEL="${GOVERNANCE_LEVEL:-standard}"
# LEVEL comes from the environment; the no-jq log lines are hand-built JSON, so only safe
# characters may reach them.
SAFE_LEVEL="$(printf '%s' "$LEVEL" | tr -cd 'A-Za-z0-9_-')"
BLOCK="${BLOCK_ON_THREAT:-false}"
CATEGORIES=""
LOG_FILE="logs/copilot/governance/audit.log"

# Extract prompt text from Copilot input (JSON with userMessage field)
PROMPT=""
if command -v jq &>/dev/null; then
  PROMPT=$(echo "$INPUT" | jq -r '.userMessage // .prompt // empty' 2>/dev/null || echo "")
fi
if [[ -z "$PROMPT" ]]; then
  PROMPT="$INPUT"
fi

# Threat detection patterns organized by category
# Each pattern has: category, description, severity (0.0-1.0)
THREATS_FOUND=()

# The credential patterns the detector uses to decide "is this a threat".
CRED_PATTERNS=(
  "(api[_-]?key|secret[_-]?key|password|token)[[:space:]]*[:=][[:space:]]*['\"]?[[:alnum:]_]{8,}"
  "(aws_access_key|AKIA[0-9A-Z]{16})"
)

# What must never be written to the log is a different, deliberately wider question: "could any of
# this be a secret". Reusing the detection patterns for it leaked: [[:alnum:]_]{8,} stops at the first
# hyphen or dot, so password=abcdefgh-LEAKME9876 logged "-LEAKME9876" and a JWT logged everything
# after its header. So: the whole value after the key, up to whitespace or the closing quote (an
# escaped quote does not close it; one left open by a truncated match runs to the end), plus bare
# JWTs and AWS key IDs anywhere.
SQ="'"
REDACT_PATTERNS=(
  "(api[_-]?key|secret([_-]?key)?|password|passwd|pwd|token)[[:space:]]*[:=][[:space:]]*(\"([^\"\\\\]|\\\\.)*\"?|${SQ}([^${SQ}\\\\]|\\\\.)*${SQ}?|[^[:space:]${SQ}\"]+)"
  "eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"
  "AKIA[0-9A-Z]{16}"
)

# Replaces every secret-shaped substring with its first and last 4 characters, or [REDACTED]
# when there are too few to hide anything - the same rule scan-secrets uses. Applied to the evidence
# of EVERY category, not just credential_exposure: a greedy pattern such as "export .* to external"
# captures whatever lies between its anchors, and once captured a password was logged whole.
redact_credentials() {
  local text="$1" p m r
  for p in "${REDACT_PATTERNS[@]}"; do
    while IFS= read -r m; do
      [[ -z "$m" ]] && continue
      if (( ${#m} <= 12 )); then r="[REDACTED]"; else r="${m:0:4}...${m: -4}"; fi
      text="${text//"$m"/"$r"}"
    done < <(printf '%s' "$text" | grep -oiE "$p" || true)
  done
  printf '%s' "$text"
}

check_pattern() {
  local pattern="$1"
  local category="$2"
  local severity="$3"
  local description="$4"

  if echo "$PROMPT" | grep -qiE "$pattern"; then
    local evidence
    evidence=$(echo "$PROMPT" | grep -oiE "$pattern" | head -1)
    evidence=$(redact_credentials "$evidence")
    local evidence_encoded
    evidence_encoded=$(printf '%s' "$evidence" | base64 | tr -d '\n')
    THREATS_FOUND+=("$category	$severity	$description	$evidence_encoded")
  fi
}

# Data exfiltration signals
check_pattern "send[[:space:]]+(all|every|entire)[[:space:]]+[[:alnum:]_]+[[:space:]]+to[[:space:]]+" "data_exfiltration" "0.8" "Bulk data transfer"
check_pattern "export[[:space:]]+.*[[:space:]]+to[[:space:]]+(external|outside|third[_-]?party)" "data_exfiltration" "0.9" "External export"
check_pattern "curl[[:space:]]+.*[[:space:]]+-d[[:space:]]+" "data_exfiltration" "0.7" "HTTP POST with data"
check_pattern "upload[[:space:]]+.*[[:space:]]+(credentials|secrets|keys)" "data_exfiltration" "0.95" "Credential upload"

# Privilege escalation signals
check_pattern "(sudo|as[[:space:]]+root|admin[[:space:]]+access|runas[[:space:]]+/user)" "privilege_escalation" "0.8" "Elevated privileges"
check_pattern "chmod[[:space:]]+777" "privilege_escalation" "0.9" "World-writable permissions"
check_pattern "add[[:space:]]+.*[[:space:]]+(sudoers|administrators)" "privilege_escalation" "0.95" "Adding admin access"

# System destruction signals
check_pattern "(rm[[:space:]]+-rf[[:space:]]+/|del[[:space:]]+/[sq]|format[[:space:]]+c:)" "system_destruction" "0.95" "Destructive command"
check_pattern "(drop[[:space:]]+database|truncate[[:space:]]+table|delete[[:space:]]+from[[:space:]]+[[:alnum:]_]+[[:space:]]*(;|[[:space:]]*$))" "system_destruction" "0.9" "Database destruction"
check_pattern "wipe[[:space:]]+(all|entire|every)" "system_destruction" "0.9" "Mass deletion"

# Prompt injection signals
check_pattern "ignore[[:space:]]+(previous|above|all)[[:space:]]+(instructions?|rules?|prompts?)" "prompt_injection" "0.9" "Instruction override"
check_pattern "you[[:space:]]+are[[:space:]]+now[[:space:]]+(a|an)[[:space:]]+(assistant|ai|bot|system|expert|language[[:space:]]+model)([^[:alnum:]_]|$)" "prompt_injection" "0.7" "Role reassignment"
check_pattern "(^|\n)[[:space:]]*system[[:space:]]*:[[:space:]]*you[[:space:]]+are" "prompt_injection" "0.6" "System prompt injection"

# Credential exposure signals
check_pattern "${CRED_PATTERNS[0]}" "credential_exposure" "0.9" "Possible hardcoded credential"
check_pattern "${CRED_PATTERNS[1]}" "credential_exposure" "0.95" "AWS key exposure"

# Log the prompt event
if [[ ${#THREATS_FOUND[@]} -gt 0 ]]; then
  # Build threats JSON array
  THREATS_JSON="["
  FIRST=true
  MAX_SEVERITY="0.0"
  for threat in "${THREATS_FOUND[@]}"; do
    IFS=$'\t' read -r category severity description evidence_encoded <<< "$threat"
    evidence=""  # was `local evidence` - illegal outside a function, it aborted the script on every detected threat
    evidence=$(printf '%s' "$evidence_encoded" | base64 -d 2>/dev/null || echo "[redacted]")

    if [[ "$FIRST" != "true" ]]; then
      THREATS_JSON+=","
    fi
    FIRST=false

    CATEGORIES+="${CATEGORIES:+,}$category"
    if [[ $HAVE_JQ -eq 1 ]]; then
      THREATS_JSON+=$(jq -Rn \
        --arg cat "$category" \
        --arg sev "$severity" \
        --arg desc "$description" \
        --arg ev "$evidence" \
        '{"category":$cat,"severity":($sev|tonumber),"description":$desc,"evidence":$ev}')
    fi

    # Track max severity
    # awk, not bc: bc is absent on Git Bash and many slim Linux images, and the old `|| echo 0`
    # fallback silently left max_severity at 0.0 for every threat.
    if awk -v a="$severity" -v b="$MAX_SEVERITY" 'BEGIN { exit !(a > b) }'; then
      MAX_SEVERITY="$severity"
    fi
  done
  THREATS_JSON+="]"

  if [[ $HAVE_JQ -eq 1 ]]; then
    jq -Rn \
      --arg timestamp "$TIMESTAMP" \
      --arg level "$LEVEL" \
      --arg max_severity "$MAX_SEVERITY" \
      --argjson threats "$THREATS_JSON" \
      --argjson count "${#THREATS_FOUND[@]}" \
      '{"timestamp":$timestamp,"event":"threat_detected","governance_level":$level,"threat_count":$count,"max_severity":($max_severity|tonumber),"threats":$threats}' \
      >> "$LOG_FILE"
  else
    # Reduced line: every value here is a fixed identifier or a number, so no escaping is needed -
    # which is exactly why the matched evidence is left out rather than hand-escaped.
    printf '{"timestamp":"%s","event":"threat_detected","governance_level":"%s","threat_count":%d,"max_severity":%s,"categories":"%s","log":"reduced-no-jq"}\n' \
      "$TIMESTAMP" "$SAFE_LEVEL" "${#THREATS_FOUND[@]}" "$MAX_SEVERITY" "$CATEGORIES" >> "$LOG_FILE"
  fi

  echo "[WARN] Governance: ${#THREATS_FOUND[@]} threat signal(s) detected (max severity: $MAX_SEVERITY)"
  for threat in "${THREATS_FOUND[@]}"; do
    IFS=$'\t' read -r category severity description _evidence_encoded <<< "$threat"
    echo " [CRITICAL] [$category] $description (severity: $severity)"
  done

  # In strict/locked mode or when BLOCK_ON_THREAT is true, exit non-zero to block
  if [[ "$BLOCK" == "true" ]] || [[ "$LEVEL" == "strict" ]] || [[ "$LEVEL" == "locked" ]]; then
    echo "[BLOCKED] Prompt blocked by governance policy (level: $LEVEL)"
    exit 1
  fi
else
  if [[ $HAVE_JQ -eq 1 ]]; then
    jq -Rn \
      --arg timestamp "$TIMESTAMP" \
      --arg level "$LEVEL" \
      '{"timestamp":$timestamp,"event":"prompt_scanned","governance_level":$level,"status":"clean"}' \
      >> "$LOG_FILE"
  else
    printf '{"timestamp":"%s","event":"prompt_scanned","governance_level":"%s","status":"clean","log":"reduced-no-jq"}\n' \
      "$TIMESTAMP" "$SAFE_LEVEL" >> "$LOG_FILE"
  fi
fi

exit 0
