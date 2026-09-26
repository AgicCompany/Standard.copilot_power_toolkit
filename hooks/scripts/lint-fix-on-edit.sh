#!/usr/bin/env bash
# Lint Fix On Edit Hook (bash) - mirrors lint-fix-on-edit.ps1 exactly; keep both in sync.
# Event: postToolUse. stdout is IGNORED by the host for this event, so this hook fixes files
# rather than reporting; the agent's next read sees the corrected version.
set -uo pipefail

[[ "${SKIP_LINT_FIX:-}" == "true" ]] && exit 0

payload="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

# Deliberately NOT gated on toolName - names differ per host/version. Extension check below filters.

result_type="$(printf '%s' "$payload" | jq -r '.toolResult.resultType // "success"')"
[[ "$result_type" != "success" ]] && exit 0

# toolArgs is a JSON *string*, not a nested object - it needs a second parse. Getting this wrong
# is what made tool-guardian silently no-op for months.
file_path="$(printf '%s' "$payload" | jq -r '.toolArgs // "{}"' | jq -r '.path // .file_path // .filePath // .filepath // .uri // .targetFile // .target_file // .fileName // ""')"
[[ -z "$file_path" || ! -f "$file_path" ]] && exit 0

case "$file_path" in
  */node_modules/*|*/dist/*|*/build/*|*/.next/*) exit 0 ;;
  # Generated Power Apps CLI output is overwritten wholesale by `pa app add data-source`; reformatting it
  # only creates diff noise on the next regeneration.
  */generated/*|*/src/generated/*) exit 0 ;;
esac

extensions="${LINT_FIX_EXTENSIONS:-ts,tsx,js,jsx,mjs,cjs}"
ext="${file_path##*.}"
match=0
IFS=',' read -ra allowed <<< "$extensions"
for a in "${allowed[@]}"; do
  [[ "$ext" == "$(printf '%s' "$a" | tr -d '[:space:]')" ]] && match=1 && break
done
[[ $match -eq 0 ]] && exit 0

[[ -f package.json ]] || exit 0
command -v npx >/dev/null 2>&1 || exit 0

# Best-effort throughout: a formatting hook must never break the agent's workflow.
npx --no-install eslint --fix "$file_path" >/dev/null 2>&1 || true

if [[ "${LINT_FIX_PRETTIER:-true}" == "true" ]]; then
  npx --no-install prettier --write "$file_path" >/dev/null 2>&1 || true
fi

exit 0
