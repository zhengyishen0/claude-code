---
name: journal
description: Daily journal for episodic memory
---

# Journal

Daily journal captures what happened each day. Location: `vault/journal/YYYY-MM-DD.md`

## When to Write

1. **Pre-compaction** - When context is about to be compressed, note what's important
2. **Session end** - Before `/new` or `/reset`, summarize what was done
3. **Milestones** - After completing a task, making a decision, or significant event
4. **User asks** - "Remember this", "Note this down"

## How to Write

Use Edit tool to append to today's file:

```markdown
### HH:MM - Brief title
- What was discussed/done
- Key decisions or outcomes
- Links to artifacts (commits, files, vault tasks)
```

## File Template

```markdown
# YYYY-MM-DD

## Sessions

## JJ Graph
```

## End of Day

Run `skills/journal/jj-graph.sh` to append jj graph (or set up cron).

## What NOT to Write

- Lessons → use `lesson add` (procedural memory, separate system)
- Stable facts → put in CLAUDE.md (semantic memory)
- Task details → put in vault/active/ (IVDX artifacts)

Daily log is for **episodic context** - what happened, when, brief summary.
