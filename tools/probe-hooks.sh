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

echo
if [[ $FAILURES -eq 0 ]]; then
  echo "ALL $CASES CASES PASSED"
  exit 0
fi
echo "$FAILURES of $CASES FAILED"
exit 1
