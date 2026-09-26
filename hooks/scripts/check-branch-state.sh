#!/usr/bin/env bash
# Protected Branch Guard Hook (bash) - mirrors check-branch-state.ps1; keep both in sync.
# Event: sessionStart. stdout IS parsed for this event - additionalContext is injected into the
# session. userPromptSubmitted stdout is IGNORED, so a per-prompt version is not possible.
#
# Gitflow says branch first, then work. copilot-instructions.md can make the model REFUSE to commit
# to main, but nothing told anyone they were already sitting on it with uncommitted changes.
#
# Env vars: SKIP_BRANCH_GUARD (true to disable),
#           PROTECTED_BRANCHES (comma-separated, default 'main,master,develop')
set -uo pipefail

[[ "${SKIP_BRANCH_GUARD:-}" == "true" ]] && exit 0
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

branch="$(git branch --show-current 2>/dev/null || true)"
# Detached HEAD, or a repo with no commits yet - nothing useful to say either way.
[[ -z "$branch" ]] && exit 0

protected="${PROTECTED_BRANCHES:-main,master,develop}"
case ",${protected//[[:space:]]/}," in
  *",$branch,"*) ;;
  *) exit 0 ;;
esac

changed="$(git status --porcelain 2>/dev/null || true)"
# On a protected branch with a clean tree is the NORMAL state at the start of work - warning there
# would fire in every session in every repo and train people to ignore it.
[[ -z "$changed" ]] && exit 0

count="$(printf '%s\n' "$changed" | sed '/^$/d' | wc -l | tr -d ' ')"
sample="$(printf '%s\n' "$changed" | sed '/^$/d' | head -5 | sed 's/^/  /')"
more=""
if [[ "$count" -gt 5 ]]; then more="
  ... and $((count - 5)) more"; fi

read -r -d '' msg <<EOF || true
Git state: you are on '$branch', which is a protected branch, and there are $count uncommitted change(s):

$sample$more

Gitflow (copilot-instructions.md) branches BEFORE work starts: feature/* and release/* from 'develop', hotfix/* from 'main'. Committing here is not allowed, so this work has to move to a branch eventually - and moving it later is more effort than moving it now.

Before making further changes, offer to move this onto a branch: 'git stash', create 'feature/<issue-id>-short-description', then 'git stash pop'. Do NOT commit first - that puts the commit on the protected branch, which is the thing being avoided.

The 'delivery' agent handles this. If the user says these changes are deliberate and staying put, accept that and move on - raise it once, not every turn.
EOF

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$msg" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
else
  # Minimal escaping fallback so the hook still works without jq.
  esc="$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')"
  # Nested, exactly like the jq branch above. The flat { "additionalContext": ... } shape is
  # accepted and silently discarded by the host - see docs/reference/hook-payloads.md.
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
fi
exit 0
