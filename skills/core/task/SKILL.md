---
name: task
description: Task management and execution. Use to run coding tasks from vault.
---

# Task

Manage and execute tasks from the vault.

## Usage

```bash
task exec <id>           # Execute a task
task exec 002            # Partial match
task list                # List tasks (todo)
```

## Task File Format

```yaml
---
work-path: ~/Codes/my-project
agent: executor
created: 2026-02-14
---

The task description goes here.
What needs to be done, context, etc.
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `work-path` | Yes | Directory to work in (repo root) |
| `agent` | No | Agent to use (default: none, uses system default) |
| `created` | No | Creation date |

## Execution Flow

1. Parse task.md frontmatter
2. Resolve work-path (expand ~, handle file → parent dir)
3. Validate work-path exists
4. Extract task body (content after frontmatter)
5. cd to work-path
6. Spawn: `agent -A <agent> "<task-body>"`

## Agents

Predefined agents in `agents/`:

- `executor` - General task execution with work skill integration
