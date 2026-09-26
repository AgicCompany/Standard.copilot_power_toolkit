#!/usr/bin/env bash
# Dataverse Schema Drift Hook (bash) - mirrors check-schema-drift.ps1 exactly; keep both in sync.
# Event: sessionStart. stdout IS parsed - `additionalContext` is injected into the session.
set -uo pipefail

# Every exit path logs. The hook emits nothing on the common path by design, so without this
# "no warning appeared" is indistinguishable from "never ran" or "output was dropped" - an ambiguity
# that cost a whole acceptance-test step before this existed.
#
# stdout is PARSED on sessionStart, so logging goes to a FILE ONLY. Never echo.
drift_log() {
  local dir="${SCHEMA_DRIFT_LOG_DIR:-logs/copilot/dataverse-schema-drift}"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '{"timestamp":"%s","event":"sessionStart","decision":"%s","detail":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:-}" >> "$dir/drift.log" 2>/dev/null || true
}

[[ "${SKIP_SCHEMA_DRIFT:-}" == "true" ]] && { drift_log skipped "SKIP_SCHEMA_DRIFT=true"; exit 0; }

config_path="${POWER_CONFIG:-power.config.json}"
generated_dir="${GENERATED_DIR:-src/generated}"

# jq is how this script emits JSON. Without it the hook is silently inert, which is worth recording:
# on a machine with no jq the warning simply never appears and nothing says why.
command -v jq >/dev/null 2>&1 || { drift_log no_jq "jq not installed - hook inert"; exit 0; }

# Not a Power Apps Code App, or codegen has never run - nothing to compare.
[[ -f "$config_path" ]] || { drift_log not_a_code_app "no $config_path"; exit 0; }

if [[ ! -d "$generated_dir" ]]; then
  msg="Dataverse: '$config_path' exists but '$generated_dir' does not. If this app uses Dataverse data sources, the typed services have not been generated yet - run 'pa app add data-source' before writing data access code."
  jq -n --arg ctx "$msg" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
  drift_log emitted_no_generated_dir "$generated_dir"
  exit 0
fi

# Portable mtime: GNU stat and BSD/macOS stat take different flags.
mtime_of() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

newest_generated=0
while IFS= read -r -d '' f; do
  t="$(mtime_of "$f")"
  [[ "$t" -gt "$newest_generated" ]] && newest_generated="$t"
done < <(find "$generated_dir" -type f -print0 2>/dev/null)

[[ "$newest_generated" -eq 0 ]] && { drift_log no_generated_files "$generated_dir"; exit 0; }

config_time="$(mtime_of "$config_path")"
[[ "$config_time" -le "$newest_generated" ]] && { drift_log no_drift "config $config_time <= generated $newest_generated"; exit 0; }

drift_seconds=$(( config_time - newest_generated ))
if [[ "$drift_seconds" -lt 3600 ]]; then
  drift="less than an hour"
elif [[ "$drift_seconds" -lt 172800 ]]; then
  drift="$(( drift_seconds / 3600 )) hour(s)"
else
  drift="$(( drift_seconds / 86400 )) day(s)"
fi

# Keep this message word-for-word in sync with check-schema-drift.ps1. The two had silently diverged:
# the .ps1 carried gate wording while this one still said "If data access misbehaves this session",
# which is the advisory phrasing the measured A/B showed gets read and deprioritised. A mirror is not
# verified by its twin - not for code, and not for the text that does the actual work.
msg="Dataverse schema drift: '$config_path' was modified ${drift} AFTER the newest file in '$generated_dir', so the generated services may no longer match the configured data sources.

STOP - ACT ON THIS BEFORE YOUR FIRST EDIT. This is a gate, not background information.

If the task involves reading or writing Dataverse - a query hook, a service call, a component showing records - raise this in your FIRST reply and END THE TURN. **Raising it and then proceeding in the same turn is not compliance**, and neither is \"I'll start looking at the files while you decide\". Code written against stale types looks correct, compiles, and passes tests, which is exactly why the user has to answer before it exists.

If you judge that the specific operation cannot be affected - a delete that takes only a record id, say - state that reasoning and still wait. Whether the risk is acceptable is the user's call, not yours: you cannot see what changed in Dataverse, and that is the whole point of this warning.

Why nothing else will catch it: generated types agree with themselves, so TypeScript compiles and lint passes; tests mock at the service boundary, so they pass too. It surfaces at runtime as a Dataverse error about a missing column or an unset required field, often partially - some records save, some do not.

Offer to regenerate with 'pa app refresh data-source --name <name>'. Never hand-edit '$generated_dir' - it is overwritten wholesale.

If the task does not touch Dataverse, or the user says '$config_path' was changed for unrelated reasons, proceed without raising it again."

jq -n --arg ctx "$msg" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
drift_log emitted_drift_warning "$drift"
exit 0
