# environment

Event log tool for persistent AI collaboration.

## Commands

### check
Read new events since marker and move marker forward.

```bash
claude-tools environment check
```

Returns events that appeared after the READ-MARKER line, then moves the marker to the end.

### event
Append an event to the log.

```bash
claude-tools environment event [source] [description]
claude-tools environment event [source] [task-id:status] description
```

**Examples:**
```bash
# Task events
claude-tools environment event [agent] [task-001:active] "build company website"
claude-tools environment event [agent] [task-002:ready] "research domains for task-001"

# Notes
claude-tools environment event [user] "deadline is Jan 31"

# System events
claude-tools environment event [system] [12345-a7f3c1:started] "manager started"
```

## Event Format

```
[timestamp] [source] [task-id:status] description
[timestamp] [source] description
```

- **timestamp**: ISO 8601 UTC
- **source**: user, agent, system, fs, webhook, cron
- **task-id**: task-001, task-002, etc. (optional)
- **status**: active, ready, running, done, blocked, failed, paused (optional)

## How It Works

The environment.log contains a special marker line that separates read from unread events:

```
[2024-01-15T09:00:00Z] [user] [task-001:active] build website
[2024-01-15T09:05:00Z] [agent] [task-002:ready] research domains
=================READ-MARKER=================
[2024-01-15T09:10:00Z] [user] deadline is Jan 31
```

**Above marker** = already read/processed
**Below marker** = new/unread events

- **check**: Returns everything after the marker, then moves marker to end
- **event**: Appends new event at the end (after marker)

Events are never deleted - they accumulate in the log. The marker just tracks "read up to here".

## Key Principles

1. **Marker-based reading** - Only returns unread events
2. **Append-only log** - Events never deleted, only added
3. **Simple text format** - Human-readable, grep-able
4. **Self-contained** - Log file is in tool directory
