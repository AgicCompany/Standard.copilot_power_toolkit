#!/usr/bin/env bash
# Vite Env Guard Hook (bash) - mirrors guard-vite-env.ps1; keep both in sync.
# Event: preToolUse. stdout IS parsed for this event, so denial reaches the model with a reason.
#
# Env vars: SKIP_VITE_ENV_GUARD (true to disable), VITE_ENV_GUARD_MODE (block|warn),
#           VITE_ENV_GUARD_PATTERNS (comma-separated extra name fragments),
#           VITE_ENV_GUARD_ALLOW (comma-separated exact names that are genuinely public),
#           VITE_ENV_GUARD_LOG_DIR (default logs/copilot/vite-env-guard),
#           PUBLIC_ENV_PREFIXES (comma separated, default VITE_)
set -uo pipefail

LOG_DIR="${VITE_ENV_GUARD_LOG_DIR:-logs/copilot/vite-env-guard}"
LOG_FILE="$LOG_DIR/guard.log"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# NEVER log a value - only names and decisions. A log of blocked credentials that contains the
# credentials defeats its own purpose. Failure to log must never fail the hook: a non-zero exit from
# preToolUse BLOCKS THE TOOL CALL, so logging fails open even though the guard fails closed.
guard_log() {
  local event="$1" file="$2" names="$3" mode="$4"
  { mkdir -p "$LOG_DIR" 2>/dev/null &&
    printf '{"timestamp":"%s","event":"%s","file":"%s","variables":[%s],"mode":"%s"}\n' \
      "$TIMESTAMP" "$event" "$file" "$names" "$mode" >> "$LOG_FILE"; } 2>/dev/null || true
}

[[ "${SKIP_VITE_ENV_GUARD:-}" == "true" ]] && exit 0

# The public-variable prefix is CONFIGURABLE, not hardcoded. Vite exposes VITE_; Next.js exposes
# NEXT_PUBLIC_. A guard that only knows one of them logs a clean pass while a secret ships in the
# bundle of the other - the exact fail-open this baseline exists to eliminate. Set
# PUBLIC_ENV_PREFIXES (comma separated) to serve another stack from this same guard rather than
# forking it; forked mirrors drift, and we have already paid for that lesson twice.
prefix_alt="$(printf '%s' "${PUBLIC_ENV_PREFIXES:-VITE_}" | tr -d '[:space:]' | tr ',' '|')"
[[ -z "$prefix_alt" ]] && prefix_alt="VITE_"

payload="$(cat)"
[[ -z "$payload" ]] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  # Fail open, but loudly in the log - a guard that cannot parse its input must never look healthy.
  guard_log "guard_no_jq" "" "" "n/a"
  exit 0
fi

# Two payload dialects exist in the wild - support both, do not assume either.
#   VS Code Copilot Chat : { "tool_name": ..., "tool_input": { ... } }  tool_input is an OBJECT
#   Copilot CLI docs     : { "toolName": ..., "toolArgs": "{...}" }     toolArgs is a JSON STRING
# The previous version of this script read only .toolArgs, so it never fired in VS Code Chat at all.
# Use the `//` alternative operator, NOT `if (.tool_input // empty) then ... else ... end`. In jq a
# condition that evaluates to `empty` makes the WHOLE if-expression produce nothing - `empty`
# propagates rather than being falsy - so the else branch is unreachable and $tool_args comes back
# blank. That silently disabled this guard for the entire Copilot CLI dialect: every payload, not
# just terminal writes. Caught 2026-08-03 by the first CI run of tools/probe-hooks.sh; the bash
# mirror had never been executed. guard-native-dialogs.sh always used the form below, which is why
# it passed the same case.
tool_args="$(printf '%s' "$payload" | jq -c '(.tool_input // (.toolArgs | if type == "string" then fromjson else . end) // {})' 2>/dev/null)"
[[ -z "$tool_args" || "$tool_args" == "null" ]] && exit 0

file_path="$(printf '%s' "$tool_args" | jq -r '.path // .file_path // .filePath // .filepath // .uri // .targetFile // .target_file // .fileName // ""')"

# A write tool is not the only way to create a file. Confirmed live 2026-08-03: blocked on the write
# tool, a model wrote the same secret with `Set-Content -Path .env.local` in the terminal and called it
# "the pragmatic move". A shell command carries no path argument, so path-only filtering fails OPEN on
# the one route that bypasses the guard entirely. Inspect the command string too.
command_str="$(printf '%s' "$tool_args" | jq -r '.command // .cmd // .commandLine // .command_line // .script // .input // .shellCommand // ""')"

is_terminal_write=0
if [[ -z "$file_path" && -n "$command_str" ]]; then
  if printf '%s' "$command_str" | grep -Eq '(^|[[:space:]'"'"'"=/\\])\.env(\.[A-Za-z0-9_.-]+)?([[:space:]'"'"'";|&]|$)' \
     && printf '%s' "$command_str" | grep -Eqi '((Set|Add)-Content|Out-File|Tee-Object|New-Item|[[:space:]]tee[[:space:]]|printf|echo|cat|>>?)'; then
    is_terminal_write=1
    file_path="<terminal command>"
  fi
fi

[[ -z "$file_path" ]] && exit 0

if [[ "$is_terminal_write" -eq 0 ]]; then
  # Only .env-family files. A secret in a .ts file is secrets-scanner's job.
  base="$(basename "$file_path")"
  case "$base" in
    .env|.env.*|*.env) ;;
    *) exit 0 ;;
  esac
fi

if [[ "$is_terminal_write" -eq 1 ]]; then
  # In a shell command the assignment sits mid-string inside quotes, so the line-anchored match below
  # never fires. Split each VITE_NAME=VALUE pair onto its own line first.
  content="$(printf '%s' "$command_str" | grep -Eio "($prefix_alt)[A-Z0-9_]*[[:space:]]*=[[:space:]]*[^[:space:]'\";|&]+" || true)"
else
  content="$(printf '%s' "$tool_args" | jq -r '.content // .new_str // .newText // .text // .newString // .code // .contents // .newContent // ""')"
fi
[[ -z "$content" ]] && exit 0

patterns="SECRET|KEY|TOKEN|PASSWORD|PWD|CREDENTIAL|PRIVATE|CONNECTION_STRING|CLIENT_SECRET|API_KEY|SAS|CERT"
if [[ -n "${VITE_ENV_GUARD_PATTERNS:-}" ]]; then
  extra="$(printf '%s' "$VITE_ENV_GUARD_PATTERNS" | tr ',' '|' | tr -d '[:space:]')"
  [[ -n "$extra" ]] && patterns="$patterns|$extra"
fi

# Names that cannot denote a credential whatever pattern word they contain: VITE_TOKEN_ENDPOINT is a
# URL, VITE_API_KEY_HEADER_NAME is a header name. Blocking those trains people to ignore the guard.
structural_suffixes='_(URL|ENDPOINT|ID|NAME|HEADER|PREFIX|ISSUER|AUTHORITY|TENANT|REGION|VERSION)$'

# Two sources, because the env var alone is not usable by an agent. Confirmed live 2026-08-03: a model
# correctly added the name to the `env` block of vite-env-guard.json, that needed a host reload to take
# effect, and it read the non-effect as "this path is broken" and bypassed the guard via the terminal.
# vite-env-guard.json is also baseline-owned, so the next `apply-baseline -Force` would have erased the
# exception regardless. The .allow file is project-owned and re-read on every invocation.
allow_names=""
[[ -n "${VITE_ENV_GUARD_ALLOW:-}" ]] && allow_names="${VITE_ENV_GUARD_ALLOW//[[:space:]]/}"
allow_file="${VITE_ENV_GUARD_ALLOW_FILE:-.github/vite-env-guard.allow}"
if [[ -f "$allow_file" ]]; then
  from_file="$(sed -E 's/#.*//; s/[[:space:]]//g' "$allow_file" | grep -v '^$' | tr '\n' ',' || true)"
  [[ -n "$from_file" ]] && allow_names="${allow_names:+$allow_names,}$from_file"
fi
allow_names="$(printf '%s' "$allow_names" | tr '[:lower:]' '[:upper:]')"

offenders=""
allowed=""
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  printf '%s' "$line" | grep -Eiq "^[[:space:]]*(export[[:space:]]+)?($prefix_alt)[A-Z0-9_]*($patterns)[A-Z0-9_]*[[:space:]]*=[[:space:]]*[^[:space:]]" || continue

  name="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*(export[[:space:]]+)?//; s/[[:space:]]*=.*//')"
  value="$(printf '%s' "$line" | sed -E 's/^[^=]*=[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//')"
  upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"

  # A URL is not a credential, whatever the variable is called.
  if printf '%s' "$value" | grep -Eq '^https?://'; then allowed="$allowed $name"; continue; fi
  if printf '%s' "$upper" | grep -Eq "$structural_suffixes"; then allowed="$allowed $name"; continue; fi
  # Explicit, auditable exceptions for values that really are public (App Insights instrumentation
  # key, Stripe publishable key). The fix for a false positive is a named exception, NOT renaming
  # the variable until the check stops firing.
  if [[ -n "$allow_names" ]]; then
    if printf '%s' ",$allow_names," | grep -Fq ",$upper,"; then
      allowed="$allowed $name"; continue
    fi
  fi

  offenders="$offenders$name=<redacted>"$'\n'
done <<< "$content"

json_names() { printf '%s' "$1" | tr ' ' '\n' | sed '/^$/d' | sort -u | sed 's/.*/"&"/' | paste -sd, -; }

[[ -n "${allowed// /}" ]] && guard_log "guard_allowed_exception" "$file_path" "$(json_names "$allowed")" "n/a"

if [[ -z "$offenders" ]]; then
  guard_log "guard_passed" "$file_path" "" "n/a"
  exit 0
fi

offenders="$(printf '%s' "$offenders" | sort -u)"
offender_names="$(printf '%s' "$offenders" | sed 's/=<redacted>//' | tr '\n' ' ')"

reason="Refused: this variable's prefix compiles its value into the client bundle, where anyone who loads the app can read it.

Offending assignments in ${file_path}:
${offenders}

Any variable with a public prefix (VITE_ in Vite, NEXT_PUBLIC_ in Next) ships to the browser - this is not configuration, it is a published credential.

Fix: drop the public prefix so the value stays server-side, or move the secret to a Power Platform connection / server-side proxy and have the client call that instead. See instructions/vite-env-and-secrets.instructions.md.

If this value is genuinely public (an Application Insights connection string, a Stripe publishable key), it is allowed - record the exception instead of working around the block:

  Append the EXACT variable name, one per line, to .github/vite-env-guard.allow

That file is read on every invocation, so it takes effect on your very next tool call with no reload. Then retry the original write. Do NOT edit the env block in .github/hooks/vite-env-guard.json - that needs a host reload to apply and is overwritten by the next baseline sync.

This guard inspects terminal commands as well as file writes, so writing the same value with Set-Content, echo, or a shell redirect is not a way around it, and doing so is not compliance. If the allow file does not resolve the block, STOP and tell the user what you were trying to write and why you believe the value is public. Let them decide - do not rename the variable until the check stops firing, which removes the guard for that value permanently and leaves no record of the decision."

mode="${VITE_ENV_GUARD_MODE:-block}"
if [[ "$mode" == "warn" ]]; then
  guard_log "guard_warned" "$file_path" "$(json_names "$offender_names")" "$mode"
  jq -n --arg ctx "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
  exit 0
fi

guard_log "guard_denied" "$file_path" "$(json_names "$offender_names")" "$mode"

# Emit BOTH known envelopes - the host parses whichever it recognises and ignores the other.
# Which dialect this host honours for the RESPONSE is still unverified, so do not drop either.
jq -n --arg reason "$reason" \
  '{permissionDecision: "deny", permissionDecisionReason: $reason,
    hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
exit 0
