---
name: lesson
description: Learn behavioral rules from experience (WHEN->DO->BECAUSE patterns)
---

# lesson

A CLI tool for AI to learn behavioral rules from experience.

## Pattern

```
WHEN [context] -> DO [action] -> BECAUSE [reason]
WHEN [context] -> DO NOT [action] -> BECAUSE [reason]
```

## Commands

```bash
lesson add <pattern>                 # Add global lesson
lesson add --skill=X <pattern>       # Add skill-scoped lesson
lesson list [--skill=X] [--from=ai|user]
lesson show <id>
lesson wrong <id> [--reason=...]     # Mark incorrect (delete)
lesson promote <id> --to=<skill>     # Bake into SKILL.md
lesson search <query>
lesson load --skill=X                # Load lessons (for skills)
```

## Examples

```bash
lesson add "WHEN multiple approaches -> DO pick minimal -> BECAUSE user preference"
lesson add --skill=config "WHEN editing -> DO read first -> BECAUSE avoid wrong assumptions"
lesson wrong 002 --reason "too specific"
lesson promote 003 --to=browser
```
