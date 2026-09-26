#!/usr/bin/env bash
#
# Native Dialog Guard (bash) - mirrors guard-native-dialogs.ps1 exactly; keep both in sync.
#
# Event: preToolUse. Denies writing window.confirm / alert / prompt into app source.
#
# WHY A HOOK AND NOT AN INSTRUCTION: the rule exists in the instruction layer and was ignored four
# times on 2026-08-01/02, the last time explicitly - "despite the baseline instructions naming them
# as the styling authority - I used a native window.confirm()". A denial is the only mechanism in
# this baseline that has never been talked around, because a refusal has to be dealt with rather
# than weighed against the task.
#
# In a Code App the consequence is silent: the iframe sandbox lacks allow-modals, so confirm()
# returns false immediately, the destructive action never happens, nothing throws, and build, lint
# and tests all pass. The <dialog> ELEMENT is unaffected by that flag and is not blocked here.
#
# Environment variables:
#   SKIP_DIALOG_GUARD    - "true" to disable entirely
#   DIALOG_GUARD_MODE    - block (default) | warn
#   DIALOG_GUARD_LOG_DIR - log directory override

set -uo pipefail

LOG_DIR="${DIALOG_GUARD_LOG_DIR:-logs/copilot/native-dialog-guard}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

guard_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || return 0
  printf '{"timestamp":"%s","event":"%s","file":"%s","calls":"%s","mode":"%s"}\n' \
    "$TS" "$1" "${2:-}" "${3:-}" "${4:-n/a}" >> "$LOG_DIR/guard.log" 2>/dev/null || true
}

[[ "${SKIP_DIALOG_GUARD:-}" == "true" ]] && exit 0

# Only a Code App needs this. There confirm() runs inside an iframe sandboxed without allow-modals
# and silently returns false - a functional failure, which is what earned a blocking hook. In a
# plain React app confirm() works; preferring the UI library's dialog there is a convention the
# instruction layer carries. Code Apps are recognised as dataverse-schema-drift does it.
[[ -f "${POWER_CONFIG:-power.config.json}" ]] || { guard_log not_a_code_app "" "" "n/a"; exit 0; }

command -v jq >/dev/null 2>&1 || { guard_log no_jq "" "" "n/a"; exit 0; }

raw="$(cat)"
[[ -z "$raw" ]] && exit 0

# Two payload dialects, same as guard-vite-env.sh. Not gated on tool name.
file_path="$(jq -r '
  (.tool_input // (.toolArgs | if type == "string" then fromjson else . end) // {}) as $a
  | ($a.path // $a.file_path // $a.filePath // $a.filepath // $a.uri // $a.targetFile // $a.target_file // $a.fileName // empty)
' <<<"$raw" 2>/dev/null)"
# A write tool is not the only way to create a file. Confirmed live 2026-08-03 against the sibling
# guard: blocked on the write tool, the model wrote the same content with `Set-Content -Path ...` in
# the terminal and called it "the pragmatic move". A shell command carries no path argument, so
# path-only filtering fails OPEN on the one route that defeats the guard. Extract the target path out
# of the command instead, so every check below still applies to it unchanged.
command_str="$(jq -r '
  (.tool_input // (.toolArgs | if type == "string" then fromjson else . end) // {}) as $a
  | ($a.command // $a.cmd // $a.commandLine // $a.command_line // $a.script // $a.input // $a.shellCommand // empty)
' <<<"$raw" 2>/dev/null)"

is_terminal_write=0
if [[ -z "$file_path" && -n "$command_str" ]]; then
  if printf '%s' "$command_str" | grep -Eqi '((Set|Add)-Content|Out-File|Tee-Object|New-Item|[[:space:]]tee[[:space:]]|printf|echo|cat|>>?)'; then
    hit="$(printf '%s' "$command_str" | grep -Eoi "[^[:space:]'\";|&]+\.(tsx?|jsx?)([^A-Za-z0-9]|$)" | head -n 1 | sed -E 's/[^A-Za-z0-9]$//')"
    if [[ -n "$hit" ]]; then
      file_path="$hit"
      is_terminal_write=1
    fi
  fi
fi

[[ -z "$file_path" ]] && exit 0

case "$file_path" in
  *.ts|*.tsx|*.js|*.jsx) ;;
  *) exit 0 ;;
esac
# Both bare and nested forms - a relative path like 'node_modules/x/i.js' has no leading segment, so
# */node_modules/* alone misses it. Caught by the discrimination probe.
case "$file_path" in
  node_modules/*|dist/*|build/*|.github/*) exit 0 ;;
  */node_modules/*|*/dist/*|*/build/*|*/.github/*) exit 0 ;;
  *.test.ts|*.test.tsx|*.test.js|*.test.jsx|*.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx) exit 0 ;;
esac

if [[ "$is_terminal_write" -eq 1 ]]; then
  # The whole command is the payload - the source being written is embedded in it as a quoted string.
  content="$command_str"
else
  content="$(jq -r '
    (.tool_input // (.toolArgs | if type == "string" then fromjson else . end) // {}) as $a
    | ($a.content // $a.new_str // $a.newText // $a.text // $a.newString // $a.code // $a.contents // $a.newContent // empty)
  ' <<<"$raw" 2>/dev/null)"
fi
[[ -z "$content" ]] && exit 0

# Strip comment lines first - documenting the ban is not violating it.
offenders="$(printf '%s\n' "$content" \
  | grep -vE '^\s*(//|\*|/\*)' \
  | grep -oE '(^|[^A-Za-z0-9_.$])(window[[:space:]]*\.[[:space:]]*)?(confirm|alert|prompt)[[:space:]]*\(' \
  | grep -oE '(confirm|alert|prompt)' | sort -u | paste -sd, - 2>/dev/null)"

if [[ -z "$offenders" ]]; then
  guard_log guard_passed "$file_path" "" "n/a"
  exit 0
fi

reason="Refused: ${offenders} cannot be used in a Power Apps Code App.

File: ${file_path}

Code Apps run inside an iframe whose sandbox lacks 'allow-modals'. There, confirm() does not show a dialog - it returns false IMMEDIATELY. So \"confirm before deleting\" becomes \"silently never delete\". Nothing throws. The build passes, lint passes, tests pass, and it works perfectly on localhost, which is where you will test it.

Fix: use the UI library this project is configured for. Read the 'ui' field in .github/.baseline-manifest.json - 'shadcn' means AlertDialog ('pnpm dlx shadcn@latest add alert-dialog'), 'fluent' means its Dialog. Installing it is part of finishing the work, not a separate task.

Do NOT hand-roll a dialog to avoid the install. A native <dialog> element does work here - it is unaffected by allow-modals - but a bespoke one matches nothing else in the app, ignores its theming and a11y conventions, and has to be maintained by hand forever, all to skip one install.

This guard inspects terminal commands as well as file writes, so writing the same code with Set-Content, echo, or a shell redirect is not a way around it, and doing so is not compliance.

If this genuinely is not a Code App, or this file never runs in the iframe, set SKIP_DIALOG_GUARD=true for the session. Do not work around this by renaming the call or splitting it across lines. If none of the above fits, STOP and tell the user what you were trying to write and why - let them decide."

MODE="${DIALOG_GUARD_MODE:-block}"
if [[ "$MODE" == "warn" ]]; then
  guard_log guard_warned "$file_path" "$offenders" "warn"
  jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $r}}'
  exit 0
fi

guard_log guard_denied "$file_path" "$offenders" "block"
jq -n --arg r "$reason" '{
  permissionDecision: "deny",
  permissionDecisionReason: $r,
  hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}
}'
exit 0
