# Copilot's Memory Stores — Where They Live, How To Audit Them

Behavioural rules are in `instructions/memory.instructions.md`. This file holds the paths and the
commands, and exists because a memory store you cannot inspect is a configuration you cannot debug.

## The three stores

| Store | Path | Scope | In the repo? |
|---|---|---|---|
| **Global** | `%APPDATA%\Code\User\globalStorage\github.copilot-chat\memory-tool\memories\` | your account — every project, every workspace | no |
| **Workspace** | `%APPDATA%\Code\User\workspaceStorage\<id>\GitHub.copilot-chat\memory-tool\memories\` | this workspace | no |
| **Repo** | `.github/docs/project-memory.md` | this repository | **yes** |

Both built-in stores load automatically at the start of a conversation, **before** any `applyTo`
glob is evaluated, and are read back as settled convention. Neither appears in a PR diff.

## Audit everything

```powershell
# global - the one people forget exists
Get-ChildItem "$env:APPDATA\Code\User\globalStorage\github.copilot-chat\memory-tool\memories" -Recurse -File |
  ForEach-Object { "=== $($_.Name) ($($_.LastWriteTime)) ==="; Get-Content $_.FullName }

# every workspace, not just the current one
Get-ChildItem "$env:APPDATA\Code\User\workspaceStorage\*\GitHub.copilot-chat\memory-tool\memories" -Recurse -File |
  ForEach-Object { "=== $($_.FullName) ==="; Get-Content $_.FullName }
```

Clear one workspace's notes (leave the directory; it recreates itself):

```powershell
Remove-Item "$env:APPDATA\Code\User\workspaceStorage\<id>\GitHub.copilot-chat\memory-tool\memories\*" -Recurse -Force
```

## Why the global tier matters

Discovered 2026-07-28, and only because a model cited *"the user's preference"* for something no repo
file stated. Asked where that was written, it answered accurately: a global `workflow-preferences.md`
authored a month earlier, during unrelated work. Its first line was:

> *"Before executing tasks, review relevant files under workspace `.github/` (instructions, prompts,
> chatmodes) and apply those best practices first."*

That is this baseline's entire purpose, encoded account-wide. Every adherence result measured on that
machine was therefore *"the baseline **on this account**"* — a fresh machine may bind far more weakly.
A second file carried Power Apps Canvas formula rules into every project, including plain React ones.

**Two consequences for testing:**

1. **Clearing workspace notes between steps does not touch the global store.** If a test plan tells
   you to clear memory, it means both.
2. **Comparisons stay valid, generalisation does not.** Runs on one machine share the same global
   notes, so model-vs-model differences are real. What you cannot conclude from them is how the
   baseline behaves for someone else.

Before concluding that an instruction file binds — or doesn't — read the global store.

## Before a clean-room measurement

Move the global store aside rather than deleting it:

```powershell
$g = "$env:APPDATA\Code\User\globalStorage\github.copilot-chat\memory-tool"
Rename-Item $g "memory-tool.bak"     # restore by renaming back
```

Then reload the window. Anything that still binds is the repo configuration doing the work.
