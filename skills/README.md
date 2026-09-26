# Skills

Skills are on-demand walkthroughs for a specific task. Unlike instructions, which load
automatically when a matching file is in play, a skill loads only when the model decides its
description fits what you asked for.

## Which skills you have

**The ones in this folder** — and which ones those are depends on the profile this project was set
up with. There is deliberately no list here: a fixed catalogue in a file that ships to every profile
is wrong for most of them, and it goes stale the first time a skill is added.

To see what is installed and when each applies:

```powershell
Select-String -Path .github/skills/*/SKILL.md -Pattern '^description:' | ForEach-Object Line
```

```bash
grep -h "^description:" .github/skills/*/SKILL.md
```

Each description says when the skill should be read and, for most, when it should **not**. The
`TRIGGER` / `SKIP` wording is deliberate: it is what the model matches against.

## Using them

You do not invoke a skill by name. Describe the task, and the model reads the skill whose
description matches:

```
Add a submit that also writes the request lines and updates the asset status
```

That matches `custom-api-authoring` if your profile installed it, because its description triggers
on a write touching more than one row.

**Skill loading is discretionary.** If a task clearly falls under a skill and the model did not use
it, say so explicitly — *"use the custom-api-authoring skill"* — rather than assuming it was read.

## Structure

Each skill is a folder with a `SKILL.md`:

- **YAML frontmatter** — `name` (matching the folder name) and `description`.
- **The body** — the procedure. Good skills tell the reader to *check* a precondition rather than
  assume it, and name the command or file that settles a fact instead of restating it.

A skill is loaded in full when triggered, so its size is a real cost even though loading is
on demand.

## Adding your own

Project-specific skills belong in this folder alongside the baseline's. Keep the description
trigger-shaped — what to read it before, and when to skip it — since that is the only part the
model sees before deciding.

## References

- [About agent skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
