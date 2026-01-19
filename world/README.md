# world

Single source of truth for agent coordination.

## Commands

### write

Unified write command for events and tasks.

```bash
# Write event
world write --event <type> [--session <id>] <content>

# Write task
world write --task <id> <status> [<trigger>] [<description>] [--need <criteria>]

# Write agent status (shorthand for event)
world write --agent <status> <session-id> <content>
```

**Examples:**
```bash
# Events
world write --event "git:commit" "fix: login bug"
world write --event "system" --session abc123 "task started"

# Tasks
world write --task "login-fix" "pending" "now" "Fix login" --need "tests pass"
world write --task "login-fix" "running"
world write --task "login-fix" "done"

# Agent status
world write --agent start abc123 "Starting task"
world write --agent finish abc123 "Task completed"
```

### read

Unified read command with filtering.

```bash
world read [options]
```

**Options:**
- `--event` - Only show events
- `--task` - Only show tasks
- `--type <type>` - Filter events by type
- `--status <status>` - Filter tasks by status
- `--session <id>` - Filter by session ID
- `--since <date>` - Filter entries since date
- `--tail <n>` - Show last n entries

**Examples:**
```bash
world read                           # All entries
world read --event                   # Only events
world read --task                    # Only tasks
world read --event --type git:commit # Events of specific type
world read --task --status pending   # Pending tasks
world read --session abc123          # All entries for session
world read --tail 20                 # Last 20 entries
```

### supervisor

Run supervisors for task management.

```bash
world supervisor once     # Run both once
world supervisor daemon   # Run continuously
world supervisor level1   # Only state enforcement
world supervisor level2   # Only verification
```

## Data Types

### Event (facts, one-time)

Events are immutable facts that have occurred.

**Format:**
```
[timestamp] [event] <type> | <content>
```

**Event Types:**
- `git:commit`, `git:push` - Git operations
- `system` - System events
- `user` - User actions
- `task:<id>` - Task lifecycle events
- `browser`, `file`, `api` - Tool operations
- `agent:<status>:<session>` - Agent lifecycle

### Task (to-dos with lifecycle)

Tasks are work items with state and triggers.

**Format:**
```
[timestamp] [task] <id> | <status> | <trigger> | <description> | need: <criteria>
```

**Task Statuses:**
- `pending` - Waiting for trigger
- `running` - Currently executing
- `done` - Completed successfully
- `failed` - Failed, needs attention

**Triggers:**
- `now` - Execute immediately
- `<datetime>` - Execute at specific time
- `after:<task-id>` - Execute after another task completes

## Task Lifecycle

```
Task created (pending)
      │
      ▼
Trigger condition met
      │
      ▼
spawn_task → status = running
      │
      ▼
Task Agent executes
      │
      ├─── Success → status = done
      │
      └─── Failure → status = failed
```

## Key Principles

1. **Two commands** - `read` and `write` only
2. **Two data types** - Events (facts) and Tasks (to-dos)
3. **Plain text** - Human readable, grep-able with `rg`
4. **Append-only** - Never delete, only add
5. **Unified format** - `|` separators for parsing
