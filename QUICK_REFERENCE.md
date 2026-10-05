# Progressive Disclosure Quick Reference

> **TL;DR:** Keep core instructions minimal, reference detailed docs, let the AI load what it needs.

## The Golden Rules

1. **Core file <= 70 lines** - Only universal, always-relevant info. Enforced by `tools/lint-baseline.ps1`.
2. **Reference, don't repeat** - Point to detailed docs instead of inline content
3. **Layer your context** - Core → Specific → Advanced
4. **Let AI decide** - Agent loads details when task requires them

## File Roles

| File Type | When Loaded | Purpose | Keep Under |
|-----------|-------------|---------|------------|
| `copilot-instructions.md` | Always | Universal rules | 70 lines |
| `.github/instructions/*.md` | File pattern match | Language-specific | 150 lines |
| `.github/agents/*.md` | selected in the agent picker (NOT `@agent`) | Domain expertise | 200 lines |
| `.github/prompts/*.md` | Slash command | Task templates | 100 lines |
| `.github/docs/*.md` | Reference only | Detailed procedures | No limit |

## Which Route To Use (measured, not guessed)

Instructions are loaded the same way regardless of how you ask. **How you ask still changes whether
they get applied.** Measured on this baseline with GPT-5.3-Codex, identical prompt, identical
instruction files:

| Route | Component conventions met |
|---|---|
| Direct: *"Create a Counter component..."* | **2 of 5** - typed props, `className`; no test, no `cn()`, no styling setup |
| `small-plan` -> `tdd` handoff | **4 of 5** - added `cn()`, a colocated test, and noticed the test runner was missing |

No instruction files changed between those two runs. Three rounds of sharpening the prose moved the
direct route from 2/5 to 2/5; changing the route moved it to 4/5.

**Why:** a scope-minimal model in execution mode optimises for the smallest correct diff. In planning
or critique mode it is answering *"what does doing this properly involve?"* - and that question
surfaces the conventions already sitting in context.

**So:**

1. **Anything beyond a one-line change: start with `plan` or `small-plan`**, then follow the handoff
   buttons: *Create Feature Branch* (`delivery`), then *Implement Plan* or *Start With Tests* (`tdd`),
   then `review` -> `checklist`.
   **Plan with a strong model, execute with a cheaper one.** Pick the strong model in the picker for
   the plan; press *Create Feature Branch* (the `delivery` agent creates or confirms the branch); then
   switch to a cheaper model before pressing *Implement Plan* or *Start With Tests*. Both live only on
   `delivery`, and both check the current branch before their first edit — buttons show after every
   reply, so that check, not the button's position, is what stops work landing on `main`/`develop`.
   Measured on a live Code App project: plans written this way and executed by a low-cost model
   produced PRs with 0-1 low-severity review findings; when the cheap model stopped, every stop traced
   to a gap in the plan, not to execution. A small task with an exact, self-contained prompt (files,
   expected behaviour, test cases, commands to run) needed no plan step at all. Keep the strong model
   for security-sensitive code and for anything the plan leaves open.
2. **Never treat `review` alone as sign-off.** Run its `checklist` handoff. Confirmed failure: on the
   same file, `review` praised a hand-rolled `cn()` helper as "standard, fast path for class merging"
   while `checklist` correctly flagged it as a convention violation.
3. **Some conventions no route fixes.** The Tailwind-installed precondition failed in all six
   contexts tested, so it is enforced mechanically by the `build-gate` hook instead of by prose.
4. **Scope a review narrowly, and name the convention.** Measured on the same agent, same session:

   | Prompt | Result |
   |---|---|
   | *"Review AccountsList, its hook, and CreateAccountForm"* | generic quality findings — unhandled promise rejection, a missing test |
   | *"Check `form.tsx` against the project's UI primitive setup"* | cross-referenced 5 files, found a Base UI / Radix split **and** an ineffective context guard nobody had noticed |

   A broad scope produces breadth; a narrow scope anchored to a convention produces depth. If you
   want convention enforcement rather than a second opinion, **ask about one thing and name the
   convention it should be checked against.**

## Good vs Bad Examples

### ✅ Good: Progressive Disclosure

```markdown
# AGENTS.md (45 lines)

## Overview
Tech: Node.js, React, TypeScript
Purpose: Document collaboration platform

## How to Work
- Build: see .github/docs/building.md
- Test: see .github/docs/testing.md
- Style: see .github/docs/style.md
```

### ❌ Bad: Context Bloat

```markdown
# AGENTS.md (450 lines)

## Overview
[200 lines of history and details]

## Build Process
[100 lines of every edge case]

## Testing
[150 lines of every scenario]
```

## Context Loading Example

When editing `App.tsx`:

```
✓ Loaded: copilot-instructions.md (100 lines)
✓ Loaded: react-ts.instructions.md (90 lines)
✓ Loaded: Current file content
✓ Available: App.test.tsx (if open)

❌ Not loaded: csharp-dotnet.instructions.md
❌ Not loaded: git.instructions.md (until needed)
❌ Not loaded: @agents (until invoked)
```

**Context used:** ~400 lines  
**Context saved:** ~800 lines for actual code understanding

## Quick Checklist

When writing instructions:

- [ ] Is this always relevant? → Core file
- [ ] Is this language-specific? → instructions/
- [ ] Is this a reusable task? → prompts/
- [ ] Is this detailed reference? → docs/
- [ ] Can I reference instead of repeat?
- [ ] Is it under the line limit?

## Performance Impact

| Instruction Count | AI Performance |
|-------------------|----------------|
| 0-70 lines | ⭐⭐⭐⭐⭐ Optimal |
| 70-150 lines | ⭐⭐⭐⭐ Good |
| 150-200 lines | ⭐⭐⭐ Acceptable |
| 200+ lines | ⭐⭐ Degraded |
| 300+ lines | ⭐ Poor |

## Common Mistakes

1. **Instruction Bloat** - Adding "just in case" information
2. **Repetition** - Same info in multiple files
3. **Historical Baggage** - Outdated edge cases that no longer apply
4. **Over-documentation** - Documenting every possible scenario
5. **No Layering** - Everything in one flat file

## How to Fix Bloat

1. **Audit** - Count lines in core files
2. **Extract** - Move detailed content to referenced docs
3. **Reference** - Point to extracted docs
4. **Test** - Verify AI can still find info when needed
5. **Monitor** - Review quarterly for drift

## Further Reading

- Full guide: [PROGRESSIVE_DISCLOSURE.md](https://github.com/AgicCompany/Standard.copilot_power_toolkit/blob/main/PROGRESSIVE_DISCLOSURE.md)
  and structure guide: [README.md](https://github.com/AgicCompany/Standard.copilot_power_toolkit/blob/main/README.md),
  in the baseline's own repository (neither is copied into projects)
- HumanLayer blog: https://www.hlyr.dev/blog/writing-a-good-claude-md
- Copilot docs: https://docs.github.com/en/copilot

---

**Remember:** Less is more. The AI is smart—give it pointers, not novels.
