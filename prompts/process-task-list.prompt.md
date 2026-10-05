---
description: "Manage the task list in a markdown file to track progress toward completing a PRD"
agent: 'agent'
---
# Task List Management

## Language Support (EN/IT)
- This prompt supports both English and Italian inputs.
- Reply in the same language used by the user.
- Keep task checkbox formatting and file paths unchanged.

Guidelines for managing task lists in markdown files to track progress on completing a PRD

## Task Implementation
- **One sub-task at a time:** Do **NOT** start the next sub‑task until you ask the user for permission and they say “yes” or "y"
- **Completion protocol:**  
  1. When you finish a **sub‑task**, immediately mark it as completed by changing `[ ]` to `[x]`.  
  2. If **all** subtasks underneath a parent task are now `[x]`, also mark the **parent task** as completed.  
- **Version control** (same policy in the Italian prompt — keep them aligned):
  1. Before starting, if the project is a git repository, check the working tree is clean
     (`git status --porcelain` prints nothing). If it is not, ask the user how to proceed.
  2. Follow `instructions/git.instructions.md` and the project's Gitflow rules.
  3. When a **parent task** is complete, propose a conventional commit message for it. **Do not
     commit yourself** — the user, or the `delivery` agent (the only agent that runs git), commits.
- Stop after each sub‑task and wait for the user’s go‑ahead.

## Task List Maintenance

1. **Update the task list as you work:**
   - Mark tasks and subtasks as completed (`[x]`) per the protocol above.
   - Add new tasks as they emerge.

2. **Maintain the “Relevant Files” section:**
   - List every file created or modified.
   - Give each file a one‑line description of its purpose.

## AI Instructions

When working with task lists, the AI must:

1. Regularly update the task list file after finishing any significant work.
2. Follow the completion protocol:
   - Mark each finished **sub‑task** `[x]`.
   - Mark the **parent task** `[x]` once **all** its subtasks are `[x]`.
3. Add newly discovered tasks.
4. Keep “Relevant Files” accurate and up to date.
5. Before starting work, check which sub‑task is next.
6. After implementing a sub‑task, update the file and then pause for user approval.
