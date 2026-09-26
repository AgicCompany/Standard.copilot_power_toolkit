---
description: 'Resume work in a new chat — loads project context and durable memory, then proposes the next smallest slice.'
agent: 'agent'
---

# New Chat Bootstrap Prompt

Copy/paste this at the start of a new chat, when context from the previous one is gone.

---
Read these first, then continue from the last unfinished piece of work:

1) `.github/copilot-instructions.md` — always-loaded conventions
2) `.github/project-context.md` — this project's stack, integrations, constraints
3) `.github/docs/project-memory.md` — durable decisions and corrections (if it exists)

Then, before writing any code:

- Summarise the current state in 6-10 bullets, drawn from those files and the working tree —
  not from assumptions about what a project like this usually contains.
- Run `git status` and `git branch --show-current`. Say what you find. If there is uncommitted
  work on a protected branch, raise that before anything else.
- Propose the **next smallest shippable slice** with explicit acceptance criteria, and stop.
  Do not start implementing until the slice is agreed.

While working:

- Follow the auto-applied files in `.github/instructions/` — they load by file pattern and are
  already in context for the files you touch.
- Beyond a small change, start from `plan` or `small-plan` rather than coding directly.

After the slice is done:

- Run the build and the tests, and report the actual output — including failures.
- Append anything durable you learned to `.github/docs/project-memory.md`: a corrected approach,
  a non-obvious repo fact, a decision worth not re-litigating. One line each, with the why.
---
