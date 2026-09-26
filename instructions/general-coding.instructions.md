---
description: General coding instructions and best practices for all programming languages
applyTo: '**'
---

# General Coding Instructions

## Language Support (EN/IT)
- These instructions support both English and Italian inputs.
- Reply in the same language used by the user.
- Keep code snippets, commands, and file paths unchanged.

## Code Quality Standards

### Naming Conventions
- Use **descriptive, self-documenting names** for variables, functions, and classes
- Prefer `isLoading`, `hasError`, `canSubmit` over generic names like `flag`, `status`
- Use consistent naming patterns within the same codebase
- Avoid abbreviations unless they're widely understood in the domain

### Function Design
- **Single Responsibility**: Each function should do one thing well
- **Pure functions** when possible - no side effects, predictable outputs
- Keep functions **small** (ideally under 20 lines)
- Use **early returns** to reduce nesting and improve readability

### Error Handling
- **Always handle errors explicitly** - never ignore or suppress them
- **Fail fast** with clear, actionable error messages
- **Log errors appropriately** without exposing sensitive information
- Use appropriate error types for the context (exceptions, error objects, etc.)

### Code Structure
- **DRY Principle**: Don't Repeat Yourself - extract common logic
- **Consistent indentation** and formatting throughout the codebase
- **Group related functionality** together
- **Separate concerns** - business logic, UI, data access should be distinct

## Security First
- **Validate all inputs** at system boundaries
- **Sanitize outputs** to prevent injection attacks
- **Never hardcode secrets** - use environment variables or secure vaults
- **Principle of least privilege** - grant minimal necessary permissions

## Performance Considerations
- **Optimize for readability first**, performance second
- **Avoid premature optimization** - measure before optimizing
- **Use appropriate data structures** for the task
- **Consider memory usage** and avoid unnecessary allocations

## Documentation
- **Write self-documenting code** with clear variable and function names
- **Comment the 'why', not the 'what'** - explain business logic and complex decisions
- **Keep comments up-to-date** with code changes
- **Document public APIs** and complex algorithms

## Testing Principles
- **Write testable code** - avoid tightly coupled dependencies
- **Test edge cases** and error conditions
- **Use descriptive test names** that explain the scenario
- **Keep tests simple** and focused on single behaviors

## Version Control
- **Make atomic commits** - one logical change per commit
- **Write clear commit messages** following conventional commit format
- **Keep commits small** and focused
- **Review code before committing** - check for issues and formatting

## Asking the user: never for what you can check, never for permission to break a rule

Questions are not free. Each one stops the work and spends the user's attention, so spend it only on
things they alone can answer.

**Do not ask what the repo can tell you.** If the answer is in a file, read the file. "Does this
field exist?", "is this dependency installed?", "which version is this?", "is there a test for this?"
are all lookups, not decisions. Asking makes the user do your verification, and their answer then
gets treated as authoritative and never re-checked - so a wrong guess from them becomes a fact.

**Do not offer, as a selectable option, something the project forbids.** If an instruction file,
skill or guard rules an approach out, it is not a menu item. Presenting it as a choice launders the
violation through the user: they click it, and afterwards the record shows they asked for it. Say the
constraint exists and offer the routes that comply.

**Never write an option that cannot be true.** Options are read as a statement about what is
possible, and a plausible-but-impossible one is worse than no question at all, especially
pre-selected.

Do ask about genuine tradeoffs that are the user's to make - scope, effort, which of two valid
designs, anything touching a live environment or costing real money.

> Measured 2026-08-03: told a generated model was missing a field, an agent asked the user *"does
> this field already exist in Dataverse?"* - answerable by one grep of a file in the repo - offered
> *"already exists but generation didn't pick it up"*, which the generator's full-metadata behaviour
> makes impossible, and offered *"manually patch the generated file"*, which the project explicitly
> forbids. Three separate failures in two questions.

## General Principles
- **KISS**: Keep It Simple, Stupid - prefer simple solutions
- **YAGNI**: You Aren't Gonna Need It - don't over-engineer
- **Composition over inheritance** where applicable
- **Fail fast and fail clearly** with meaningful error messages
- **Be consistent** with existing codebase patterns and conventions

## Code Review Checklist
- Does the code solve the problem correctly?
- Is it readable and maintainable?
- Are there any security vulnerabilities?
- Are edge cases handled appropriately?
- Is error handling comprehensive?
- Are there adequate tests?
- Does it follow the project's coding standards?
