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
expect_clean_run() {
  local label="$1" script="$2" payload="$3" parsed_stdout="${4:-}"
  CASES=$((CASES + 1))
  local out err rc crash bad_json=""
  out="$(cd "$SMOKE" && printf '%s' "$payload" | bash "$SCRIPTS/$script" 2>"$WORK/stderr")"; rc=$?
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

echo "--- smoke: every bash hook survives a realistic payload ---"
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
