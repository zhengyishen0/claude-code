# world

Single source of truth for agent coordination in YouPu (有谱).

## Commands

### event
Log an event (facts, no tracking needed).

```bash
claude-tools world event <source> <identifier> <output>
```

**Sources:** chrome, bash, file, api, system, user

**Examples:**
```bash
claude-tools world event chrome "airbnb.com/s/Paris" "clicked Search, 24 listings"
claude-tools world event bash "git-status" "clean working directory"
claude-tools world event file "src/config.json" "modified"
claude-tools world event user "abc123" "captcha solved: boats"
```

### agent
Log agent status (projects, tracked until verified/failed).

```bash
claude-tools world agent <status> <session-id> <output>
```

**Statuses:** start, active, finish, verified, retry, failed

**Examples:**
```bash
claude-tools world agent start abc123 "Book Tokyo flights | need: confirmation number"
claude-tools world agent active abc123 "searching flights"
claude-tools world agent finish abc123 "Booked JAL $450, confirmation #XYZ"
claude-tools world agent verified abc123 "success criteria met"
claude-tools world agent retry abc123 "prices not found, try again"
claude-tools world agent failed abc123 "captcha required | need: solve captcha"
```

### check
Read new entries since last marker.

```bash
claude-tools world check [agent-id]
```

Returns entries after last READ-MARKER, then adds audit trail and new marker.

### query
Common queries on the log.

```bash
claude-tools world query <type> [pattern]
```

**Types:**
- `active` - All active agents
- `pending` - Agents awaiting verification (status=finish)
- `failed` - All failed agents
- `verified` - All verified agents
- `events [source]` - All events (optionally filter by source)
- `agent <session-id>` - All entries for a session
- `recent [N]` - Last N entries (default 20)

## Log Format

```
# Events (facts)
[timestamp][event:source][identifier] output

# Agents (projects)
[timestamp][agent:status][session-id] output | need: criteria
```

## Agent Lifecycle

```
start → active → finish → verified ✓
                    ↓
                  retry → active → finish → verified ✓
                    ↓
                  failed → (user input) → retry → active ...
```

## Key Principles

1. **Plain text** - Human readable, grep-able with `rg`
2. **Append-only** - Never delete, only add
3. **Two types** - Events (facts) and Agents (tracked projects)
4. **Marker-based reading** - Only see new entries after last check
5. **| need:** - Success criteria (start) or blocker requirement (failed)
