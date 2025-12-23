# environment

Event log tool for persistent AI collaboration.

## Commands

### check
Read new events since marker and track who read them.

```bash
claude-tools environment check [agent-id]
```

Returns events that appeared after the last READ-MARKER line (or "no new events" if none). **Always** adds a read event to track who checked, then adds a new marker at the end.

The optional `agent-id` parameter identifies who is reading (blank if not provided). Automated agents should provide their ID (e.g., "manager-abc123").

**Important:** This command always adds a read event and marker, even when there are no new events, creating a complete audit trail of all check operations.

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

The environment.log contains READ-MARKER lines that separate read from unread events. When events are read, a read event is added to create an audit trail:

```
[2024-01-15T09:00:00Z] [user] [task-001:active] build website
[2024-01-15T09:05:00Z] [agent] [task-002:ready] research domains
[2024-01-15T09:05:30Z] [agent manager-abc123] checked all 2 events above
=================READ-MARKER=================
[2024-01-15T09:10:00Z] [user] deadline is Jan 31
[2024-01-15T09:12:00Z] [agent] [task-003:ready] design mockup
[2024-01-15T09:12:45Z] [agent manager-abc123] checked all 2 events above
=================READ-MARKER=================
[2024-01-15T09:15:00Z] [user] [task-001:done] website complete
```

**Above last marker** = already read/processed (with read events showing who read when)
**Below last marker** = new/unread events

- **check**: Returns everything after last marker, adds a read event, adds new marker at end
- **event**: Appends new event at the end (after last marker)

Events and markers are never deleted - they accumulate in the log (append-only). Read events create an audit trail of processing.

## Key Principles

1. **Marker-based reading** - Only returns unread events (after last marker)
2. **Fully append-only** - Events and markers never deleted, only added
3. **Read event tracking** - Each check adds: `[timestamp] [agent xxx] checked all N events above` (xxx is blank if no agent-id provided)
4. **Audit trail** - Read events and multiple markers show complete processing history
5. **Agent identification** - Optional agent-id (blank by default), automated agents should provide their ID
6. **Simple text format** - Human-readable, grep-able
7. **Self-contained** - Log file is in tool directory
