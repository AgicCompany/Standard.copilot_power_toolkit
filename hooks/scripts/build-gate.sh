#!/bin/bash
#
# Build Gate Hook
# Runs TypeScript type-checking (and lint, if configured) at session end so a
# session doesn't quietly end in a broken state. Deterministic - doesn't rely
# on an agent remembering to run/report build status.
#
# Environment variables:
#   GATE_MODE       - "warn" (log only) or "block" (exit non-zero on failure) (default: warn)
#   SKIP_BUILD_GATE - "true" to disable entirely (default: unset)
#   GATE_LOG_DIR    - Directory for gate logs (default: logs/copilot/build-gate)
#   GATE_RUN_LINT   - "false" to skip the lint step even if a lint script exists (default: true)
#   GATE_CONVENTIONS - "off" | "warn" | "block" (default: warn). Mechanical convention checks.
#                      "block" fails the gate on its own, regardless of GATE_MODE.

set -uo pipefail

if [[ "${SKIP_BUILD_GATE:-}" == "true" ]]; then
  echo "[SKIP]  Build gate skipped (SKIP_BUILD_GATE=true)"
  exit 0
fi

if [[ ! -f package.json ]]; then
  echo "[SKIP]  Build gate skipped (no package.json - not a Node project)"
  exit 0
fi

# Registered on BOTH sessionEnd and Stop. In VS Code Copilot Chat sessionEnd never fires but Stop
# fires after EVERY completed turn, so without throttling a full tsc + lint would run after every
# message. Verified live - see docs/reference/event-probe.md.
MIN_INTERVAL="${GATE_MIN_INTERVAL_SEC:-180}"
STAMP_DIR="${GATE_LOG_DIR:-logs/copilot/build-gate}"
STAMP_FILE="$STAMP_DIR/.last-run"
if [[ "$MIN_INTERVAL" -gt 0 && -f "$STAMP_FILE" ]]; then
  LAST=$(cat "$STAMP_FILE" 2>/dev/null || echo 0)
  NOW=$(date -u +%s)
  ELAPSED=$(( NOW - LAST ))
  if [[ "$ELAPSED" -lt "$MIN_INTERVAL" ]]; then
    echo "[SKIP]  Build gate throttled (${ELAPSED}s since last run, minimum ${MIN_INTERVAL}s). Set GATE_MIN_INTERVAL_SEC=0 to disable."
    exit 0
  fi
fi
mkdir -p "$STAMP_DIR" 2>/dev/null || true
date -u +%s > "$STAMP_FILE" 2>/dev/null || true

MODE="${GATE_MODE:-warn}"
LOG_DIR="${GATE_LOG_DIR:-logs/copilot/build-gate}"
RUN_LINT="${GATE_RUN_LINT:-true}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/gate.log"

# Detect package manager from lockfile - don't assume pnpm/npm/yarn.
PM="npm"
if [[ -f pnpm-lock.yaml ]]; then
  PM="pnpm"
elif [[ -f yarn.lock ]]; then
  PM="yarn"
elif [[ -f package-lock.json ]]; then
  PM="npm"
fi

FAILURES=()
TYPECHECK_RAN=false
LINT_RAN=false

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '
}

# ---------------------------------------------------------------------------
# Type check
# ---------------------------------------------------------------------------
if [[ -f tsconfig.json ]]; then
  TYPECHECK_RAN=true
  # A root tsconfig.json using project references (common in Vite scaffolds: "files": [] plus
  # "references": [...]) is NOT traversed by plain `tsc --noEmit` - only `tsc --build` (-b) follows
  # references. Using --noEmit there would silently check zero files and falsely report success
  # (confirmed empirically: it disagreed with `npm run build`, whose own script uses `tsc -b`).
  # Individual referenced tsconfigs in the Vite template already set `"noEmit": true`, so `-b` alone
  # (no --noEmit flag, which build mode doesn't reliably honor anyway) won't emit build output.
  if grep -q '"references"' tsconfig.json 2>/dev/null; then
    echo "[CHECK] Running tsc -b (project references detected) ..."
    if ! TSC_OUTPUT=$(npx --no-install tsc -b 2>&1); then
      echo "$TSC_OUTPUT" | tail -30
      FAILURES+=("typecheck")
    fi
  else
    echo "[CHECK] Running tsc --noEmit ..."
    if ! TSC_OUTPUT=$(npx --no-install tsc --noEmit 2>&1); then
      echo "$TSC_OUTPUT" | tail -30
      FAILURES+=("typecheck")
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Lint (only if the project actually defines a lint script)
# ---------------------------------------------------------------------------
if [[ "$RUN_LINT" == "true" ]] && command -v node &>/dev/null; then
  HAS_LINT_SCRIPT=$(node -e "try{const s=require('./package.json').scripts||{};process.stdout.write(s.lint?'yes':'no')}catch(e){process.stdout.write('no')}" 2>/dev/null || echo "no")
  if [[ "$HAS_LINT_SCRIPT" == "yes" ]]; then
    LINT_RAN=true
    echo "[CHECK] Running $PM run lint ..."
    if ! LINT_OUTPUT=$("$PM" run lint 2>&1); then
      echo "$LINT_OUTPUT" | tail -30
      FAILURES+=("lint")
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Convention checks - mechanical only, informational by default
# ---------------------------------------------------------------------------
# These exist because some conventions cannot be enforced by instruction prose. The Tailwind check
# was added after that instruction failed to bind in six separate contexts (direct prompt, planning,
# TDD execution, refactor, checklist review, code review). A component can emit Tailwind classes into
# a project with no Tailwind installed and it will compile, typecheck, lint, build and pass every
# test while rendering completely unstyled. No other gate here can see that.
# Every check must be mechanical - no judgement calls. Informational unless GATE_CONVENTIONS=block.
CONVENTION_MODE="${GATE_CONVENTIONS:-warn}"
CONVENTIONS=()

if [[ "$CONVENTION_MODE" != "off" ]]; then
  # Each file is judged against its NEAREST package.json, not the root one. In a repository whose
  # app sits in a subfolder (src/frontend/ with its own package.json), the root package.json lists
  # neither tailwindcss nor tailwind-merge, so both checks below used to fire on a correctly set-up
  # app. Fallback: the root package.json.
  # The scan covers the whole repository, not just ./src: apps live at src/frontend/, apps/web/src/
  # and other layouts, and ownership is settled per file by nearest_pkg anyway.
  SCAN_EXCLUDES=(--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir=coverage)
  nearest_pkg() {
    local d
    d="$(dirname "$1")"
    while [[ "$d" != "." && "$d" != "/" && -n "$d" ]]; do
      [[ -f "$d/package.json" ]] && { printf '%s' "$d/package.json"; return; }
      d="$(dirname "$d")"
    done
    printf '%s' "package.json"
  }
  # Prints the files (from stdin) whose nearest package.json declares none of the given packages.
  files_lacking() {
    local f pkg
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      pkg="$(nearest_pkg "$f")"
      grep -qE "\"($1)\"[[:space:]]*:" "$pkg" 2>/dev/null || printf '%s\n' "$f"
    done
  }

  # 1. Tailwind utility classes with no Tailwind installed. The suffix list is deliberately
  #    restrictive so bespoke class names (my-class, counter, text-wrapper) do not false-positive.
  TW_VALUE='([0-9]+|px|auto|full|screen|none|xs|sm|md|lg|xl|2xl|3xl|primary|secondary|muted|accent|destructive|foreground|background|center|left|right|start|end|between|around|bold|semibold|medium|light)'
  TW_PATTERN="className[[:space:]]*=.*((flex|grid|hidden|truncate|relative|absolute|sticky)|(bg|text|border|rounded|px|py|pt|pb|pl|pr|mx|my|mt|mb|ml|mr|gap|items|justify|shadow|font|space|inset|w|h|p|m|z)-${TW_VALUE})"
  TW_FILES=$(grep -rlE "$TW_PATTERN" --include='*.tsx' --include='*.jsx' "${SCAN_EXCLUDES[@]}" . 2>/dev/null | files_lacking 'tailwindcss' | head -10 || true)
  if [[ -n "$TW_FILES" ]]; then
    CONVENTIONS+=("tailwind_not_installed")
    echo ""
    echo "[WARN] tailwind_not_installed: Tailwind utility classes found, but 'tailwindcss' is not in"
    echo "       the package.json that owns these files. These classes resolve to nothing - the UI"
    echo "       renders unstyled and no other check can detect it."
    printf '       %s\n' $TW_FILES
  fi

  # 2. A local cn() helper while nothing merges classes = a hand-rolled stub that concatenates
  #    classes instead of resolving conflicting utilities. tailwind-merge (clsx + twMerge, older
  #    shadcn) and shadcn's own `cn` package (newer shadcn: `export { cn } from "cn"`) both count.
  # ([^[:alnum:]_]|$), not \b: \b is a GNU extension to ERE, not POSIX.
  CN_FILES=$(grep -rlE 'export[[:space:]]+(function|const)[[:space:]]+cn([^[:alnum:]_]|$)' --include='*.ts' --include='*.tsx' "${SCAN_EXCLUDES[@]}" . 2>/dev/null | files_lacking 'tailwind-merge|cn' | head -10 || true)
  if [[ -n "$CN_FILES" ]]; then
    CONVENTIONS+=("cn_without_tailwind_merge")
    echo ""
    echo "[WARN] cn_without_tailwind_merge: A local cn() helper exists but neither 'tailwind-merge' nor"
    echo "       shadcn's 'cn' package is installed, so it concatenates classes instead of resolving"
    echo "       conflicts. Install what the project's shadcn version uses (shadcn-ui.instructions.md, Composing)."
    printf '       %s\n' $CN_FILES
  fi

  # 3. Components with no colocated test. src/components/ui/** is shadcn CLI output, not ours.
  if [[ -d src/components ]]; then
    MISSING_TESTS=""
    while IFS= read -r comp; do
      [[ -z "$comp" ]] && continue
      case "$comp" in
        *.test.tsx|*.spec.tsx|*.stories.tsx) continue ;;
        */components/ui/*) continue ;;
      esac
      base="${comp%.tsx}"
      if [[ ! -f "${base}.test.tsx" ]]; then
        MISSING_TESTS="${MISSING_TESTS}${comp}"$'\n'
      fi
    done < <(find src/components -type f -name '*.tsx' 2>/dev/null)
    if [[ -n "$MISSING_TESTS" ]]; then
      CONVENTIONS+=("component_without_test")
      echo ""
      echo "[WARN] component_without_test: Component(s) with no colocated .test.tsx."
      echo "       react-ts.instructions.md lists a colocated test as part of the definition of done."
      printf '%s' "$MISSING_TESTS" | head -10 | sed 's/^/       /'
    fi
  fi
fi

BLOCK_REQUESTED=false
[[ "$MODE" == "block" ]] && BLOCK_REQUESTED=true

if [[ ${#CONVENTIONS[@]} -gt 0 ]]; then
  if [[ "$CONVENTION_MODE" == "block" ]]; then
    FAILURES+=("conventions")
    # GATE_CONVENTIONS=block must block on its own. Making it depend on GATE_MODE as well would mean
    # setting it to 'block' silently does nothing while GATE_MODE stays 'warn' - two flags whose
    # interaction you have to reason about to predict the exit code.
    BLOCK_REQUESTED=true
  else
    echo "       Set GATE_CONVENTIONS=block to fail the gate on these, or =off to disable."
  fi
  CONVENTIONS_JSON=$(printf '"%s",' "${CONVENTIONS[@]}")
  CONVENTIONS_JSON="[${CONVENTIONS_JSON%,}]"
else
  CONVENTIONS_JSON="[]"
fi

if [[ "$TYPECHECK_RAN" == "false" && "$LINT_RAN" == "false" && ${#CONVENTIONS[@]} -eq 0 ]]; then
  echo "[SKIP]  Nothing to gate (no tsconfig.json, no lint script)"
  printf '{"timestamp":"%s","event":"gate_skipped","mode":"%s","reason":"nothing_to_check"}\n' \
    "$TIMESTAMP" "$MODE" >> "$LOG_FILE"
  exit 0
fi

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  FAILURES_JSON=$(printf '"%s",' "${FAILURES[@]}")
  FAILURES_JSON="[${FAILURES_JSON%,}]"
  printf '{"timestamp":"%s","event":"gate_failed","mode":"%s","package_manager":"%s","failures":%s,"conventions":%s}
' \
    "$TIMESTAMP" "$MODE" "$PM" "$FAILURES_JSON" "$CONVENTIONS_JSON" >> "$LOG_FILE"

  echo ""
  echo "[FAIL] Build gate failed: ${FAILURES[*]}"
  if [[ "$BLOCK_REQUESTED" == "true" ]]; then
    echo "[BLOCKED] Session flagged: fix the above before considering this session's work done."
    echo "  Set GATE_MODE=warn to log without blocking."
    exit 1
  else
    echo "[TIP] Set GATE_MODE=block to make this a hard stop instead of a warning."
    exit 0
  fi
fi

CONVENTION_NOTE=""
if [[ ${#CONVENTIONS[@]} -gt 0 ]]; then
  CONVENTION_NOTE=" - ${#CONVENTIONS[@]} convention finding(s) above (informational)"
fi
echo "[OK] Build gate passed (typecheck ran: $TYPECHECK_RAN, lint ran: $LINT_RAN, via $PM)${CONVENTION_NOTE}"
printf '{"timestamp":"%s","event":"gate_passed","mode":"%s","package_manager":"%s","typecheck_ran":%s,"lint_ran":%s,"conventions":%s}
' \
  "$TIMESTAMP" "$MODE" "$PM" "$TYPECHECK_RAN" "$LINT_RAN" "$CONVENTIONS_JSON" >> "$LOG_FILE"
exit 0
