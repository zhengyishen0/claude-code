---
name: vault
description: Async task collaboration via vault. Use when working on tracked tasks or when user drops a note.
---

# Vault Workflow

Async collaboration between human and AI through shared documents.

## Structure

```
vault/
├── index.md          # Task list
├── tasks/            # Task files (NNN-slug.md)
├── files/            # All outputs (NNN-slug/)
├── journal/          # Daily logs (YYYY-MM-DD.md)
└── archive/          # Done tasks
```

## Two Entry Points

| Mode | Trigger | Best for |
|------|---------|----------|
| Async | Human drops note in vault/, watch.sh triggers AI | Long research, overnight |
| Sync | Human chats with Claude directly | Quick tasks, real-time |

Both modes read/write to the same vault.

## Where to Write

| What | Where | Example |
|------|-------|---------|
| Task tracking | `tasks/NNN-slug.md` | Status, idea, progress, feedback |
| Work outputs | `files/NNN-slug/` | Research, code, screenshots, reports |
| Daily log | `journal/YYYY-MM-DD.md` | Session summaries, milestones |

## Task File Format

```markdown
---
status: new | working | waiting | done | dropped
submit: false
created: YYYY-MM-DD
---

## Idea
[Raw note from human]

## Understanding
[What human wants, why, what success looks like]

## Progress
(AI updates as work proceeds)

## Resources
(links to files/NNN-slug/)

---

## Feedback
(Human writes here)

## Lessons
(What was learned)
```

## Status Flow

```
new → working → waiting ⟷ working → done
                  ↓
               dropped
```

- `new` — just created
- `working` — AI in progress
- `waiting` — needs human input (set `submit: false`)
- `done` — complete
- `dropped` — abandoned

## Human Actions

1. **Create task**: Drop note in vault root (async) or ask Claude (sync)
2. **Review**: Read task file, check AI's understanding
3. **Feedback**: Write in Feedback section
4. **Submit**: Set `submit: true` to continue work
5. **Done**: AI sets status to `done`, human can archive

## AI Actions

1. **New note**: Create `tasks/NNN-slug.md` + `files/NNN-slug/`
2. **Work**: Research, execute, save outputs to `files/`
3. **Update**: Keep Progress section current
4. **Wait**: Set `waiting` + `submit: false` when need human input
5. **Complete**: Set `done` when finished

## In This Session

When working on a tracked task:
1. Update `tasks/NNN-slug.md` Progress section
2. Save outputs to `files/NNN-slug/`
3. Link resources from task file
