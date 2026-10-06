#!/usr/bin/env bash
#
# Discrimination probe for the bash hook mirrors.
#
# WHY THIS EXISTS. Every guard ships two scripts - a PowerShell one and a bash mirror - and until
# 2026-08-03 only the PowerShell side was ever executed. The mirrors were syntax-checked at best.
# On any host with bash on PATH, and under Copilot CLI, the mirror is the script that actually runs,
# so half of every guard was shipping unverified.
#
# A guard must demonstrably ALLOW as well as block. One that blocks working code trains people to
# disable guards wholesale, which is worse than having no guard.
#
# Requires jq - the guards themselves fail open without it, so a run without jq proves nothing.
# Windows note: Git Bash usually has no jq, which is why this runs in CI on ubuntu.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/hooks/scripts"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed - the guards fail open without it, so this probe would pass vacuously." >&2
  exit 2
fi

FAILURES=0
CASES=0

# Runs a guard with $2 on stdin, and asserts DENY / ALLOW.
# DENY = non-zero exit, or a permissionDecision of deny in the emitted JSON.
expect_guard() {
  local label="$1" script="$2" expected="$3" payload="$4" envs="${5:-}"
  CASES=$((CASES + 1))
  local out rc got
  # $envs is deliberately unquoted: it is a controlled "VAR=value VAR2=value" string from this file,
  # and word splitting is how `env` receives separate assignments.
  # shellcheck disable=SC2086
  out="$(printf '%s' "$payload" | env $envs bash "$SCRIPTS/$script" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]] || printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    got="DENY"
  else
    got="ALLOW"
  fi
  if [[ "$got" == "$expected" ]]; then
    printf 'ok   %-44s expect=%-5s got=%s\n' "$label" "$expected" "$got"
  else
    FAILURES=$((FAILURES + 1))
    printf 'FAIL %-44s expect=%-5s got=%s\n' "$label" "$expected" "$got"
    printf '     output: %s\n' "$out"
  fi
}

# Asserts a sessionStart hook SPEAKS (emits additionalContext) or stays QUIET.
# $4 is the env var name the script reads, so the same helper covers every sessionStart hook.
expect_session() {
  local label="$1" expected="$2" file="$3" script="$4" var="$5"
  CASES=$((CASES + 1))
  local out got nested
  out="$(env "$var=$file" bash "$SCRIPTS/$script" </dev/null 2>&1)"
  if printf '%s' "$out" | grep -q 'additionalContext'; then got="SPEAK"; else got="QUIET"; fi
  nested="-"
  if printf '%s' "$out" | grep -q 'hookSpecificOutput'; then nested="nested"; fi
  if [[ "$got" == "$expected" ]]; then
    printf 'ok   %-44s expect=%-5s got=%-5s %s\n' "$label" "$expected" "$got" "$nested"
  else
    FAILURES=$((FAILURES + 1))
    printf 'FAIL %-44s expect=%-5s got=%-5s\n' "$label" "$expected" "$got"
    printf '     output: %s\n' "$out"
  fi
}

expect_context() {
  local label="$1" expected="$2" file="$3"
  CASES=$((CASES + 1))
  local out got nested
  out="$(PROJECT_CONTEXT_FILE="$file" bash "$SCRIPTS/check-project-context.sh" </dev/null 2>&1)"
  if printf '%s' "$out" | grep -q 'additionalContext'; then got="SPEAK"; else got="QUIET"; fi
  nested="-"
  if printf '%s' "$out" | grep -q 'hookSpecificOutput'; then nested="nested"; fi
  if [[ "$got" == "$expected" ]]; then
    printf 'ok   %-44s expect=%-5s got=%-5s %s\n' "$label" "$expected" "$got" "$nested"
  else
    FAILURES=$((FAILURES + 1))
    printf 'FAIL %-44s expect=%-5s got=%-5s\n' "$label" "$expected" "$got"
  fi
}

term()  { jq -nc --arg c "$1" '{tool_name:"run_in_terminal", tool_input:{command:$c}}'; }
write() { jq -nc --arg p "$1" --arg c "$2" '{tool_name:"create_file", tool_input:{filePath:$p, content:$c}}'; }
cli()   { jq -nc --arg c "$1" '{toolName:"shell", toolArgs:({command:$c}|tostring)}'; }

CS='InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://x.applicationinsights.azure.com/'

echo "--- guard-vite-env.sh ---"
cd "$WORK"
mkdir -p .github
printf '# comment\nVITE_APPLICATIONINSIGHTS_CONNECTION_STRING\n' > .github/vite-env-guard.allow

expect_guard "terminal write, real secret"      guard-vite-env.sh DENY  "$(term "Set-Content -Path .env.local -Value 'VITE_API_KEY=sk_live_abc'")"
expect_guard "terminal write, allowlisted name" guard-vite-env.sh ALLOW "$(term "Set-Content -Path .env.local -Value 'VITE_APPLICATIONINSIGHTS_CONNECTION_STRING=$CS'")"
expect_guard "terminal echo redirect, secret"   guard-vite-env.sh DENY  "$(term 'echo "VITE_CLIENT_SECRET=hunter2" > .env')"
expect_guard "terminal, unrelated command"      guard-vite-env.sh ALLOW "$(term 'pnpm install && pnpm build')"
expect_guard "terminal, writes a .ts file"      guard-vite-env.sh ALLOW "$(term "Set-Content -Path src/config.ts -Value 'export const x = 1'")"
expect_guard "write .env with secret"           guard-vite-env.sh DENY  "$(write '.env.local' 'VITE_API_KEY=sk_live_abc')"
expect_guard "write .env.example, empty value"  guard-vite-env.sh ALLOW "$(write '.env.example' 'VITE_APPLICATIONINSIGHTS_CONNECTION_STRING=')"
expect_guard "write .env, URL value"            guard-vite-env.sh ALLOW "$(write '.env' 'VITE_TOKEN_URL=https://login.example.com/o')"
expect_guard "write .ts with secret (not ours)" guard-vite-env.sh ALLOW "$(write 'src/a.ts' 'VITE_API_KEY=sk_live_abc')"
expect_guard "CLI dialect, terminal secret"     guard-vite-env.sh DENY  "$(cli "printf 'VITE_PRIVATE_KEY=abc' > .env.production")"

# The public prefix is configurable so one guard serves Vite and Next rather than being forked.
# The pair that matters is the first two: unset, a NEXT_PUBLIC_ secret sails through - which is
# exactly what a Next project would have got from this guard before it was parameterised.
expect_guard "NEXT_PUBLIC_ secret, default prefix" guard-vite-env.sh ALLOW "$(write '.env.local' 'NEXT_PUBLIC_API_SECRET=sk_live_abc')"
expect_guard "NEXT_PUBLIC_ secret, Next config"    guard-vite-env.sh DENY  "$(write '.env.local' 'NEXT_PUBLIC_API_SECRET=sk_live_abc')" "PUBLIC_ENV_PREFIXES=NEXT_PUBLIC_"
expect_guard "both prefixes, VITE_ still caught"   guard-vite-env.sh DENY  "$(write '.env.local' 'VITE_API_KEY=sk_live_abc')"          "PUBLIC_ENV_PREFIXES=VITE_,NEXT_PUBLIC_"
expect_guard "both prefixes, NEXT_ caught"         guard-vite-env.sh DENY  "$(write '.env.local' 'NEXT_PUBLIC_CLIENT_SECRET=abc')"     "PUBLIC_ENV_PREFIXES=VITE_,NEXT_PUBLIC_"
expect_guard "Next prefix, URL value allowed"      guard-vite-env.sh ALLOW "$(write '.env' 'NEXT_PUBLIC_TOKEN_URL=https://x.example.com')" "PUBLIC_ENV_PREFIXES=NEXT_PUBLIC_"
expect_guard "unprefixed secret ignored"           guard-vite-env.sh ALLOW "$(write '.env' 'DATABASE_PASSWORD=hunter2')"                "PUBLIC_ENV_PREFIXES=VITE_,NEXT_PUBLIC_"

echo "--- guard-native-dialogs.sh ---"
# The guard enforces only in a Code App, recognised by power.config.json (or $POWER_CONFIG).
expect_guard "not a Code App, window.confirm"      guard-native-dialogs.sh ALLOW "$(write 'src/App.tsx' 'if (window.confirm("x")) y()')" "POWER_CONFIG=$WORK/absent.json"
mkdir -p "$WORK/dir-config/power.config.json"
expect_guard "power.config.json is a directory"     guard-native-dialogs.sh ALLOW "$(write 'src/App.tsx' 'if (window.confirm("x")) y()')" "POWER_CONFIG=$WORK/dir-config/power.config.json"
printf '{}' > "$WORK/power.config.json"
export POWER_CONFIG="$WORK/power.config.json"
expect_guard "terminal write .tsx, window.confirm" guard-native-dialogs.sh DENY  "$(term "Set-Content -Path src/App.tsx -Value 'if (window.confirm(1)) x()'")"
expect_guard "terminal write .ts, alert("          guard-native-dialogs.sh DENY  "$(term 'echo "alert(1)" > src/n.ts')"
expect_guard "terminal write .tsx, benign"         guard-native-dialogs.sh ALLOW "$(term "Set-Content -Path src/App.tsx -Value 'export const A = 1'")"
expect_guard "terminal, node_modules path"         guard-native-dialogs.sh ALLOW "$(term "Set-Content -Path node_modules/x/i.js -Value 'confirm(1)'")"
expect_guard "terminal, unrelated command"         guard-native-dialogs.sh ALLOW "$(term 'pnpm build')"
expect_guard "write .tsx, window.confirm"          guard-native-dialogs.sh DENY  "$(write 'src/App.tsx' 'if (window.confirm("x")) y()')"
expect_guard "write .tsx, setPrompt( identifier"   guard-native-dialogs.sh ALLOW "$(write 'src/App.tsx' 'setPrompt("hello")')"
expect_guard "write .tsx, comment mentioning it"   guard-native-dialogs.sh ALLOW "$(write 'src/App.tsx' '// window.confirm() is banned')"
expect_guard "write .test.tsx"                     guard-native-dialogs.sh ALLOW "$(write 'src/a.test.tsx' 'confirm(1)')"
expect_guard "write .md"                           guard-native-dialogs.sh ALLOW "$(write 'README.md' 'confirm(1)')"
unset POWER_CONFIG

# Without POWER_CONFIG the guard searches upwards from the written file. The old check looked only at
# the working directory, so a nested app (src/frontend/power.config.json, as in a multi-host
# template) was never recognised. Each case runs from the project root, as the host does.
expect_guard_in() {
  local dir="$1" label="$2" expected="$3" payload="$4"
  CASES=$((CASES + 1))
  local out rc got
  out="$(cd "$dir" && printf '%s' "$payload" | bash "$SCRIPTS/guard-native-dialogs.sh" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]] || printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then got="DENY"; else got="ALLOW"; fi
  if [[ "$got" == "$expected" ]]; then
    printf 'ok   %-44s expect=%-5s got=%s\n' "$label" "$expected" "$got"
  else
    FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s expect=%-5s got=%s\n     output: %s\n' "$label" "$expected" "$got" "$out"
  fi
}
NEST="$WORK/nested"; mkdir -p "$NEST/src/frontend/src" "$NEST/src/other"; printf '{}' > "$NEST/src/frontend/power.config.json"
ROOTAPP="$WORK/rootapp"; mkdir -p "$ROOTAPP/src"; printf '{}' > "$ROOTAPP/power.config.json"
PLAIN="$WORK/plain"; mkdir -p "$PLAIN/src"
C='if (window.confirm("x")) y()'
expect_guard_in "$NEST"    "nested app, file inside it"         DENY  "$(write 'src/frontend/src/App.tsx' "$C")"
expect_guard_in "$NEST"    "nested app, absolute path"          DENY  "$(write "$NEST/src/frontend/src/App.tsx" "$C")"
expect_guard_in "$NEST"    "nested app, terminal write"         DENY  "$(term "Set-Content -Path src/frontend/src/App.tsx -Value 'if (window.confirm(1)) x()'")"
expect_guard_in "$NEST"    "nested repo, file outside the app"  ALLOW "$(write 'src/other/App.tsx' "$C")"
expect_guard_in "$ROOTAPP" "root-layout app"                    DENY  "$(write 'src/App.tsx' "$C")"
expect_guard_in "$ROOTAPP" "root-layout app, backslash path"    DENY  "$(write 'src\App.tsx' "$C")"
expect_guard_in "$PLAIN"   "no power.config.json anywhere"      ALLOW "$(write 'src/App.tsx' "$C")"
# Path shapes found in review of the first version: a file: URI failed open, and textual .. segments
# walked through src/frontend and blocked a file outside the app.
expect_guard_in "$NEST"    "nested app, file: URI"              DENY  "$(write "file://$NEST/src/frontend/src/App.tsx" "$C")"
expect_guard_in "$NEST"    "nested app, file: URI with %20"     DENY  "$(write "file://$NEST/src/frontend/src/My%20Page.tsx" "$C")"
expect_guard_in "$NEST"    ".. leading out of the app"          ALLOW "$(write 'src/frontend/../other/App.tsx' "$C")"
expect_guard_in "$NEST"    ".. leading into the app"            DENY  "$(write 'src/other/../frontend/src/App.tsx' "$C")"
expect_guard_in "$NEST"    "path outside the repository"        ALLOW "$(write "$ROOTAPP/src/App.tsx" "$C")"

echo "--- check-schema-drift.sh: finds every Code App, not only the root ---"
# The hook config used to pin POWER_CONFIG=power.config.json, so a nested app was never checked.
expect_drift_in() {
  local dir="$1" label="$2" expected="$3" must_mention="${4:-}"
  CASES=$((CASES + 1))
  local out got
  out="$(cd "$dir" && env -u POWER_CONFIG -u GENERATED_DIR bash "$SCRIPTS/check-schema-drift.sh" </dev/null 2>&1)"
  if printf '%s' "$out" | grep -q 'additionalContext'; then got="SPEAK"; else got="QUIET"; fi
  if [[ "$got" == "$expected" ]] && { [[ -z "$must_mention" ]] || printf '%s' "$out" | grep -qF "$must_mention"; }; then
    printf 'ok   %-44s expect=%-5s got=%s\n' "$label" "$expected" "$got"
  else
    FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s expect=%-5s got=%s (must mention: %s)\n     output: %s\n' "$label" "$expected" "$got" "$must_mention" "$out"
  fi
}
new_app() {  # new_app <dir> <config-age: newer|older|nogen>
  mkdir -p "$1/src/generated/services"
  printf '{}' > "$1/power.config.json"; printf 'x' > "$1/src/generated/services/S.ts"
  case "$2" in
    newer) touch -d '2020-01-01' "$1/src/generated/services/S.ts" ;;
    older) touch -d '2020-01-01' "$1/power.config.json" ;;
    nogen) rm -rf "$1/src/generated" ;;
  esac
}
D="$WORK/drift"
new_app "$D/nested-drift/src/frontend" newer;  expect_drift_in "$D/nested-drift" "nested app, config newer"       SPEAK "src/frontend/power.config.json"
new_app "$D/nested-ok/src/frontend" older;     expect_drift_in "$D/nested-ok"    "nested app, generated newer"    QUIET
new_app "$D/nested-nogen/src/frontend" nogen;  expect_drift_in "$D/nested-nogen" "nested app, never generated"    SPEAK "src/frontend/src/generated"
new_app "$D/root-drift" newer;                 expect_drift_in "$D/root-drift"   "root-layout app, config newer"  SPEAK "'power.config.json' was modified"
mkdir -p "$D/none/src";                        expect_drift_in "$D/none"         "no Code App"                    QUIET
mkdir -p "$D/vendored/node_modules/pkg"; printf '{}' > "$D/vendored/node_modules/pkg/power.config.json"
expect_drift_in "$D/vendored" "power.config.json only in node_modules" QUIET
new_app "$D/two/apps/a" newer; new_app "$D/two/apps/b" newer
expect_drift_in "$D/two" "two apps, both drifting (app a)" SPEAK "apps/a/power.config.json"
expect_drift_in "$D/two" "two apps, both drifting (app b)" SPEAK "apps/b/power.config.json"

echo "--- check-project-context.sh ---"
printf '# Project Context\n- Name: Real App\n- Domain: A real domain\n' > "$WORK/filled.md"
printf '# Project Context\n- Name: Real App\n- Domain: *e.g. "something"*\n' > "$WORK/partial.md"
: > "$WORK/empty.md"

expect_context "raw template (the target case)" SPEAK "$ROOT/project-context.template.md"
expect_context "filled file"                    QUIET "$WORK/filled.md"
expect_context "filled but one hint left"       SPEAK "$WORK/partial.md"
expect_context "file absent"                    QUIET "$WORK/nope.md"
expect_context "empty file"                     QUIET "$WORK/empty.md"

# remind-memory.sh carried the same `grep -c || echo 0` bug and had been shipping with it: a memory
# file containing no dated entries fell through and emitted a reminder claiming entries existed.
echo "--- remind-memory.sh ---"
printf '# Project Memory\n\n## Decisions\n- 2026-08-03: we chose X. Why it matters: Y.\n' > "$WORK/mem-full.md"
printf '# Project Memory\n\n## Decisions\n\n*(nothing recorded yet)*\n' > "$WORK/mem-empty.md"
: > "$WORK/mem-blank.md"

expect_session "memory file with a dated entry"  SPEAK "$WORK/mem-full.md"  remind-memory.sh MEMORY_FILE
expect_session "memory file with no entries"     QUIET "$WORK/mem-empty.md" remind-memory.sh MEMORY_FILE
expect_session "memory file blank"               QUIET "$WORK/mem-blank.md" remind-memory.sh MEMORY_FILE
expect_session "memory file absent"              QUIET "$WORK/mem-nope.md"  remind-memory.sh MEMORY_FILE

# ---------------------------------------------------------------------------------------------
# SMOKE PASS - every bash hook, not just the guards above.
#
# Until 2026-09-26 this file exercised 4 of the 17 bash mirrors. The other 13 had never executed,
# and a review of the first public release found two of them crashing on every relevant call:
# guard-tool.sh (unbound variable - which, as a preToolUse hook, blocks EVERY tool call) and
# audit-prompt.sh (`local` outside a function - on exactly the prompts it exists to audit).
# Nothing here asserts behaviour; it asserts the script survives a realistic payload. That alone
# would have caught both.
# ---------------------------------------------------------------------------------------------
SMOKE="$WORK/smoke"
mkdir -p "$SMOKE"
( cd "$SMOKE" && git init -q -b main && git -c user.name=probe -c user.email=probe@example.com commit -q --allow-empty -m init )

P_PRE_VS='{"tool_name":"read_file","tool_input":{"filePath":"src/App.tsx"},"hook_event_name":"PreToolUse"}'
P_PRE_CLI='{"toolName":"view","toolArgs":"{\"path\":\"src/App.tsx\"}"}'
P_POST_VS='{"tool_name":"create_file","tool_input":{"filePath":"README.md","content":"x"},"hook_event_name":"PostToolUse"}'
P_POST_CLI='{"toolName":"edit","toolArgs":"{\"path\":\"README.md\"}","toolResult":{"resultType":"success"}}'
P_START='{"hook_event_name":"SessionStart","session_id":"probe"}'
P_PROMPT='{"prompt":"add a contacts list","hook_event_name":"UserPromptSubmit"}'
P_STOP='{"hook_event_name":"Stop","session_id":"probe"}'

# Runs a hook from inside a throwaway git repo. PASS = exit 0 and no crash signature. For a
# sessionStart hook, stdout must also be empty or valid JSON: that stdout is PARSED, and one stray
# status line silently suppresses the additionalContext of every hook in the batch.
# HOOK_PATH, when set, is the PATH the HOOK runs with; the probe's own checks keep the real PATH.
expect_clean_run() {
  local label="$1${SMOKE_SUFFIX:-}" script="$2" payload="$3" parsed_stdout="${4:-}"
  CASES=$((CASES + 1))
  local out err rc crash bad_json=""
  out="$(cd "$SMOKE" && printf '%s' "$payload" | PATH="${HOOK_PATH:-$PATH}" bash "$SCRIPTS/$script" 2>"$WORK/stderr")"; rc=$?
  err="$(cat "$WORK/stderr")"
  crash="$(printf '%s\n%s' "$out" "$err" | grep -o -E 'unbound variable|can only be used in a function|syntax error' | head -1)"
  if [[ -n "$parsed_stdout" && -n "${out// }" ]] && ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    bad_json="stdout is not JSON on a parsed event"
  fi
  if [[ $rc -eq 0 && -z "$crash" && -z "$bad_json" ]]; then
    printf 'ok   %-44s rc=0\n' "$label"
  else
    FAILURES=$((FAILURES + 1))
    printf 'FAIL %-44s rc=%s %s%s\n' "$label" "$rc" "$crash" "$bad_json"
    printf '     stdout: %s\n     stderr: %s\n' "$(printf '%s' "$out" | head -2)" "$(printf '%s' "$err" | head -2)"
  fi
}

smoke_all() {
expect_clean_run "guard-tool, VS Code shape"            guard-tool.sh            "$P_PRE_VS"
expect_clean_run "guard-tool, CLI shape"                guard-tool.sh            "$P_PRE_CLI"
expect_clean_run "guard-vite-env, VS Code shape"        guard-vite-env.sh        "$P_PRE_VS"
expect_clean_run "guard-native-dialogs, VS Code shape"  guard-native-dialogs.sh  "$P_PRE_VS"
expect_clean_run "lint-fix-on-edit, VS Code shape"      lint-fix-on-edit.sh      "$P_POST_VS"
expect_clean_run "lint-fix-on-edit, CLI shape"          lint-fix-on-edit.sh      "$P_POST_CLI"
expect_clean_run "audit-prompt"                         audit-prompt.sh          "$P_PROMPT"
expect_clean_run "log-prompt"                           log-prompt.sh            "$P_PROMPT"
expect_clean_run "audit-session-start"                  audit-session-start.sh   "$P_START" parsed
expect_clean_run "log-session-start"                    log-session-start.sh     "$P_START" parsed
expect_clean_run "check-branch-state"                   check-branch-state.sh    "$P_START" parsed
expect_clean_run "check-project-context"                check-project-context.sh "$P_START" parsed
expect_clean_run "check-schema-drift"                   check-schema-drift.sh    "$P_START" parsed
expect_clean_run "remind-memory"                        remind-memory.sh         "$P_START" parsed
expect_clean_run "audit-session-end"                    audit-session-end.sh     "$P_STOP"
expect_clean_run "log-session-end"                      log-session-end.sh       "$P_STOP"
expect_clean_run "build-gate"                           build-gate.sh            "$P_STOP"
expect_clean_run "check-licenses"                       check-licenses.sh        "$P_STOP"
expect_clean_run "scan-secrets"                         scan-secrets.sh          "$P_STOP"
}

echo "--- smoke: every bash hook survives a realistic payload ---"
smoke_all

# The same hooks with jq hidden. This runner always has jq, so the no-jq branches were never run -
# and three session hooks called jq unguarded under `set -e`, exiting 127 on every session on a
# machine without it (Git Bash on Windows usually has none). Hiding it: a PATH of symlinks to every
# command on the real PATH except jq.
NOJQ_BIN="$WORK/nojq-bin"
mkdir -p "$NOJQ_BIN"
IFS=: read -r -a path_dirs <<< "$PATH"
for d in "${path_dirs[@]}"; do
  [[ -d "$d" ]] || continue
  for f in "$d"/*; do
    n="${f##*/}"
    [[ "$n" == "jq" || -e "$NOJQ_BIN/$n" || ! -x "$f" ]] && continue
    ln -s "$f" "$NOJQ_BIN/$n" 2>/dev/null || true
  done
done
if PATH="$NOJQ_BIN" command -v jq >/dev/null 2>&1; then
  CASES=$((CASES + 1)); FAILURES=$((FAILURES + 1))
  printf 'FAIL %-44s jq is still reachable\n' "no-jq PATH hides jq"
else
  echo "--- smoke: the same hooks with jq absent ---"
  HOOK_PATH="$NOJQ_BIN" SMOKE_SUFFIX=" (no jq)"
  smoke_all
  unset HOOK_PATH SMOKE_SUFFIX

  # Exit 0 is not enough: a hook that simply exits when jq is missing would pass the pass above. Each
  # session hook must have WRITTEN its reduced record, and the record must be valid JSON (checked
  # with the probe's own jq).
  expect_reduced_record() {  # label, log file, event name
    CASES=$((CASES + 1))
    local line
    line="$(grep '"reduced-no-jq"' "$SMOKE/$2" 2>/dev/null | grep "\"event\":\"$3\"" | tail -1)"
    if [[ -n "$line" ]] && printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
      printf 'ok   %-44s %s\n' "$1" "valid reduced record"
    else
      FAILURES=$((FAILURES + 1))
      printf 'FAIL %-44s %s\n' "$1" "no valid reduced-no-jq '$3' record in $2"
    fi
  }
  expect_reduced_record "audit-session-start wrote (no jq)" logs/copilot/governance/audit.log session_start
  expect_reduced_record "audit-session-end wrote (no jq)"   logs/copilot/governance/audit.log session_end
  expect_reduced_record "log-session-start wrote (no jq)"   logs/copilot/session.log         sessionStart
fi

# build-gate convention checks must judge an app against the package.json that OWNS it. In a repo
# whose app sits in src/frontend/ with its own package.json, the root one lists neither tailwindcss
# nor tailwind-merge, and both checks used to fire on a correctly set-up app. No tsconfig and no lint
# script here, so the gate goes straight to the conventions; each fixture carries a decoy cn() inside
# node_modules, which must be ignored.
echo "--- build-gate: conventions judged against the owning package.json ---"
expect_gate_conventions() {  # label, app package.json, lib/utils.ts content, expected warnings ("none" or space list), [app folder, default src/frontend]
  CASES=$((CASES + 1))
  local dir="$WORK/gate-$CASES" app="${5:-src/frontend}" out got
  mkdir -p "$dir/$app/src/lib" "$dir/$app/node_modules/decoy"
  printf '{"name":"root"}' > "$dir/package.json"
  printf '%s' "$2" > "$dir/$app/package.json"
  printf '%s\n' 'export const A = () => <div className="flex gap-2 bg-primary" />;' > "$dir/$app/src/a.tsx"
  printf '%s\n' "$3" > "$dir/$app/src/lib/utils.ts"
  printf '%s\n' 'export function cn() {}' > "$dir/$app/node_modules/decoy/index.ts"
  out="$(cd "$dir" && GATE_MIN_INTERVAL_SEC=0 GATE_RUN_LINT=false bash "$SCRIPTS/build-gate.sh" 2>&1)"
  got="$(printf '%s\n' "$out" | grep -oE '\[WARN\] (tailwind_not_installed|cn_without_tailwind_merge)' | sed 's/\[WARN\] //' | sort | tr '\n' ' ' | sed 's/ $//')"
  [[ -z "$got" ]] && got="none"
  if [[ "$got" == "$4" ]]; then
    printf 'ok   %-44s %s\n' "$1" "$got"
  else
    FAILURES=$((FAILURES + 1))
    printf 'FAIL %-44s expected [%s] got [%s]\n' "$1" "$4" "$got"
  fi
}
expect_gate_conventions "nested app, tailwind + tailwind-merge" \
  '{"dependencies":{"tailwindcss":"4","tailwind-merge":"3"}}' 'export function cn(...a) { return a.join(" "); }' "none"
expect_gate_conventions "nested app, shadcn cn package" \
  '{"dependencies":{"tailwindcss":"4","cn":"0.4"}}' 'export { cn } from "cn";' "none"
expect_gate_conventions "nested app, nothing installed" \
  '{"dependencies":{}}' 'export function cn(...a) { return a.join(" "); }' "cn_without_tailwind_merge tailwind_not_installed"
# Outside ./src entirely (a monorepo layout): the scan used to start at ./src and saw nothing here.
expect_gate_conventions "apps/web app, nothing installed" \
  '{"dependencies":{}}' 'export function cn(...a) { return a.join(" "); }' "cn_without_tailwind_merge tailwind_not_installed" "apps/web"
expect_gate_conventions "apps/web app, all installed" \
  '{"dependencies":{"tailwindcss":"4","tailwind-merge":"3"}}' 'export function cn(...a) { return a.join(" "); }' "none" "apps/web"
# `cn` followed by its parameter list, `cnx` must not count: the POSIX boundary replacing \b.
expect_gate_conventions "cnx() is not cn()" \
  '{"dependencies":{"tailwindcss":"4"}}' 'export function cnx(...a) { return a.join(" "); }' "none"

# The smoke pass above ran every hook inside a git repo. Whatever they logged must be invisible to
# git: logs/ is not in a project's .gitignore by default, so the hooks make logs/copilot ignore itself.
# `cd` + git rather than `git -C`, and a failing git status is itself a FAIL: an empty result must
# mean "git sees nothing", never "git errored out and printed nothing".
CASES=$((CASES + 1))
if ! status_out="$(cd "$SMOKE" && git status --porcelain --untracked-files=all 2>&1)"; then
  FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s git status failed: %s\n' "hook logs invisible to git" "$status_out"
else
  leaked="$(printf '%s\n' "$status_out" | grep 'logs/' || true)"
  if [[ -f "$SMOKE/logs/copilot/.gitignore" && -z "$leaked" ]]; then
    printf 'ok   %-44s logs/copilot ignores itself\n' "hook logs invisible to git"
  else
    FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s git sees: %s\n' "hook logs invisible to git" "$(printf '%s' "$leaked" | head -3 | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------------------------------------------
# Behaviour of the scripts fixed on 2026-09-26. Each case would have failed before the fix.
# ---------------------------------------------------------------------------------------------
echo "--- guard-tool.sh: both payload dialects ---"
TG="TOOL_GUARD_LOG_DIR=$WORK/tool-guardian"
expect_guard "VS Code shape, harmless read"      guard-tool.sh ALLOW "$P_PRE_VS"  "$TG"
expect_guard "VS Code shape, rm -rf /"           guard-tool.sh DENY  "$(term 'rm -rf /')" "$TG"
expect_guard "CLI shape, harmless view"          guard-tool.sh ALLOW "$P_PRE_CLI" "$TG"
expect_guard "CLI shape, git push --force"       guard-tool.sh DENY  "$(cli 'git push --force origin main')" "$TG"

echo "--- audit-prompt.sh: a detected threat is audited, not crashed on ---"
AP="$WORK/audit"; mkdir -p "$AP"
THREAT_PROMPT='{"prompt":"set password=supersecret12345 in config","hook_event_name":"UserPromptSubmit"}'
CASES=$((CASES + 1))
( cd "$AP" && printf '%s' "$THREAT_PROMPT" | bash "$SCRIPTS/audit-prompt.sh" >/dev/null 2>&1 ); rc=$?
if [[ $rc -eq 0 ]] && grep -q '"threat_detected"' "$AP/logs/copilot/governance/audit.log" 2>/dev/null; then
  printf 'ok   %-44s rc=0, logged threat_detected\n' "threat prompt, standard level"
else
  FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s rc=%s, threat_detected not logged\n' "threat prompt, standard level" "$rc"
fi
# A credential match IS the secret. It used to be written to audit.log whole, and nothing kept logs/
# out of a project's git history.
CASES=$((CASES + 1))
if grep -rq 'supersecret12345' "$AP/logs" 2>/dev/null; then
  FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s the plaintext secret is in the audit log\n' "credential never logged whole"
elif grep -q '"evidence": *"pass\.\.\.2345"' "$AP/logs/copilot/governance/audit.log" 2>/dev/null; then
  printf 'ok   %-44s evidence redacted to pass...2345\n' "credential never logged whole"
else
  FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s redacted evidence not found\n' "credential never logged whole"
fi

# A greedy pattern from ANOTHER category can capture the credential too: "export .* to external"
# (data_exfiltration) swallowed the password whole even while the credential record was redacted.
OV="$WORK/audit-overlap"; mkdir -p "$OV"
( cd "$OV" && printf '%s' '{"prompt":"export password=supersecret12345 to external"}' | bash "$SCRIPTS/audit-prompt.sh" >/dev/null 2>&1 )
CASES=$((CASES + 1))
if grep -rq 'supersecret12345' "$OV/logs" 2>/dev/null; then
  FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s plaintext secret in another category'"'"'s evidence\n' "credential inside an overlapping match"
elif grep -q 'export pass\.\.\.2345 to external' "$OV/logs/copilot/governance/audit.log" 2>/dev/null; then
  printf 'ok   %-44s redacted inside the data_exfiltration evidence\n' "credential inside an overlapping match"
else
  FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s expected evidence not found\n' "credential inside an overlapping match"
fi

# Redaction has its own, wider patterns than detection. Detection's \w{8,} stops at a hyphen or a
# dot, and when it doubled as the redaction the rest of the value was logged: "-LEAKME9876", or a
# JWT's body and signature. Every fixture marks its secret part with LEAK; none may reach the log.
expect_redacted() {
  local label="$1" prompt="$2" want="$3" dir
  CASES=$((CASES + 1))
  dir="$WORK/redact-$CASES"; mkdir -p "$dir"
  ( cd "$dir" && printf '{"prompt":%s}' "$(jq -Rn --arg p "$prompt" '$p')" | bash "$SCRIPTS/audit-prompt.sh" >/dev/null 2>&1 )
  if grep -rqi 'LEAK' "$dir/logs" 2>/dev/null; then
    FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s secret in the log: %s\n' "$label" "$(grep -rhoi '[^"]*LEAK[^"]*' "$dir/logs" | head -1)"
  elif grep -qF "$want" "$dir/logs/copilot/governance/audit.log" 2>/dev/null; then
    printf 'ok   %-44s logged as %s\n' "$label" "$want"
  else
    FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s expected evidence %s not found\n' "$label" "$want"
  fi
}
expect_redacted "redact: hyphenated value"      'export password=abcdefgh-LEAKME9876 to external'                                    'export pass...9876 to external'
expect_redacted "redact: JWT after token="      'export token=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJMRUFLTUUifQ.LEAKsig123 to external'   'export toke...g123 to external'
expect_redacted "redact: bare JWT"              'export the jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJMRUFLTUUifQ.LEAKsig123 to external' 'export the jwt eyJh...g123 to external'
expect_redacted "redact: quoted value, spaces"  'export password="my LEAK phrase here" to external'                                'export pass...ere\" to external'
expect_redacted "redact: escaped double quote"   'export password="abcdefgh\"LEAKME9876" to external'                               'export pass...876\" to external'
expect_redacted "redact: escaped single quote"   "export password='abcdefgh\'LEAKME9876' to external"                               "export pass...876' to external"
expect_redacted "redact: quote left open"       'set password="abcdefghLEAK12345 in config'                                         'pass...2345'
expect_redacted "redact: AWS key id"            'use AKIALEAKEFGHIJKLMNOP now'                                                        'AKIA...MNOP'

CASES=$((CASES + 1))
( cd "$AP" && printf '%s' "$THREAT_PROMPT" | GOVERNANCE_LEVEL=strict bash "$SCRIPTS/audit-prompt.sh" >/dev/null 2>&1 ); rc=$?
if [[ $rc -ne 0 ]]; then
  printf 'ok   %-44s rc=%s (blocked)\n' "threat prompt, strict level" "$rc"
else
  FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s rc=0 - strict level did not block\n' "threat prompt, strict level"
fi

# Enforcement must not depend on jq. An early `exit 0` when jq was missing once made strict mode
# silently accept every prompt - including `rm -rf /`. CI has jq, so build a PATH with every tool
# EXCEPT jq and prove strict still blocks a threat, and still lets a clean prompt through.
NOJQ="$WORK/nojq-bin"; mkdir -p "$NOJQ"
for d in /usr/local/bin /usr/bin /bin; do
  [[ -d "$d" ]] || continue
  for f in "$d"/*; do [[ -e "$NOJQ/${f##*/}" ]] || ln -s "$f" "$NOJQ/${f##*/}" 2>/dev/null; done
done
rm -f "$NOJQ/jq" "$NOJQ/jq.exe"
if PATH="$NOJQ" command -v jq >/dev/null 2>&1; then
  echo "SKIP no-jq cases: could not hide jq from PATH"
else
  for case in "threat:DENY:$THREAT_PROMPT" "clean:ALLOW:{\"prompt\":\"add a contacts list\"}"; do
    kind="${case%%:*}"; rest="${case#*:}"; want="${rest%%:*}"; pl="${rest#*:}"
    CASES=$((CASES + 1))
    ( cd "$AP" && printf '%s' "$pl" | PATH="$NOJQ" GOVERNANCE_LEVEL=strict bash "$SCRIPTS/audit-prompt.sh" >/dev/null 2>&1 ); rc=$?
    got=ALLOW; [[ $rc -ne 0 ]] && got=DENY
    if [[ "$got" == "$want" ]]; then
      printf 'ok   %-44s expect=%-5s got=%-5s\n' "$kind prompt, strict, NO jq" "$want" "$got"
    else
      FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s expect=%-5s got=%-5s\n' "$kind prompt, strict, NO jq" "$want" "$got"
    fi
  done
fi

echo "--- lint-fix-on-edit.sh: finds the file in the VS Code shape ---"
LF="$WORK/lintfix"; mkdir -p "$LF/src" "$LF/fakebin"
echo '{}' > "$LF/package.json"; echo 'export const a = 1' > "$LF/src/App.tsx"
printf '#!/bin/bash\necho "$*" >> "%s/npx-calls"\n' "$LF" > "$LF/fakebin/npx"; chmod +x "$LF/fakebin/npx"
CASES=$((CASES + 1))
( cd "$LF" && printf '%s' '{"tool_name":"create_file","tool_input":{"filePath":"src/App.tsx","content":"x"}}' \
    | PATH="$LF/fakebin:$PATH" bash "$SCRIPTS/lint-fix-on-edit.sh" >/dev/null 2>&1 )
if grep -q 'eslint --fix src/App.tsx' "$LF/npx-calls" 2>/dev/null; then
  printf 'ok   %-44s eslint called on src/App.tsx\n' "VS Code shape"
else
  FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s eslint never called - path not derived\n' "VS Code shape"
fi

echo "--- check-branch-state.sh: warns on a dirty protected branch, nested ---"
BS="$WORK/branch"; mkdir -p "$BS"
( cd "$BS" && git init -q -b main && git -c user.name=probe -c user.email=probe@example.com commit -q --allow-empty -m init && echo x > dirty.txt )
CASES=$((CASES + 1))
out="$(cd "$BS" && printf '%s' "$P_START" | bash "$SCRIPTS/check-branch-state.sh" 2>/dev/null)"
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  printf 'ok   %-44s SPEAK nested\n' "dirty main"
else
  FAILURES=$((FAILURES + 1)); printf 'FAIL %-44s output: %s\n' "dirty main" "$out"
fi

echo
if [[ $FAILURES -eq 0 ]]; then
  echo "ALL $CASES CASES PASSED"
  exit 0
fi
echo "$FAILURES of $CASES FAILED"
exit 1
