---
name: vault
description: Async task collaboration via vault. Use when working on tracked tasks or when user drops a note.
---

# Vault Workflow

Async collaboration between human and AI through shared documents.

## Structure

```
Vault/
├── index.md          # Overview
├── Tasks/            # Task files (symlink to task skill data)
├── Files/            # Work outputs
├── Daily/            # Daily logs (YYYY-MM-DD.md)
├── Archive/          # Done tasks
├── Private/          # Private notes
└── Public/           # Shared notes
```

## Two Entry Points

| Mode | Trigger | Best for |
|------|---------|----------|
| Async | Human drops note in vault/, watcher triggers AI | Long research, overnight |
| Sync | Human chats with Claude directly | Quick tasks, real-time |

Both modes read/write to the same vault.

## Where to Write

| What | Where | Example |
|------|-------|---------|
| Task tracking | `Tasks/NNN-slug.md` | Task definition |
| Work outputs | `Files/NNN-slug/` | Research, code, screenshots |
| Daily log | `Daily/YYYY-MM-DD.md` | Session summaries |

## Task Execution

Tasks are managed by the `task` skill. See `zenix task --help`.

```bash
task exec <id>    # Execute a task
task list         # List tasks
```

## Human Actions

1. **Create task**: Drop note in vault root or create in Tasks/
2. **Review**: Read task file, provide feedback
3. **Execute**: Run `task exec <id>` when ready
4. **Archive**: Move to Archive/ when done

## AI Actions (async mode)

1. **New note**: Process into task
2. **Work**: Research, save to Files/
3. **Update**: Keep task file current
4. **Wait**: Set `submit: false` when need human input
