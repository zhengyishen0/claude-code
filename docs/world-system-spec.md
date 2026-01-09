# World System Specification

Single source of truth for agent coordination in YouPu (有谱).

## Philosophy

- **"件件有着落，事事有回音"** - Nothing falls through, everything gets a response
- **Simplicity** - Plain text, grep-able with `rg`
- **Log as truth** - If not in log, didn't happen
- **AI flexibility** - Convention over enforcement

---

## world.log Format

Plain text, append-only, one entry per line.

### Events
```
[timestamp][event:source][identifier] output
```

Facts. No tracking needed. High volume.

### Agents
```
[timestamp][agent:status][session-id] output | need: criteria
```

Projects. Tracked until verified/failed. Low volume.

---

## Events

### Format
```
[2026-01-09T10:00:00Z][event:source][identifier] output
```

| Field | Description | Example |
|-------|-------------|---------|
| `timestamp` | ISO 8601 UTC | `2026-01-09T10:00:00Z` |
| `event:source` | Type + origin | `event:chrome`, `event:bash` |
| `identifier` | What specifically | `airbnb.com/s/Paris`, `git-status` |
| `output` | Free-form result | `clicked Search, 24 results` |

### Sources

| Source | When | Identifier Examples |
|--------|------|---------------------|
| `chrome` | Browser action | URL, page title |
| `bash` | Command execution | command name |
| `file` | File change | file path |
| `api` | API call | endpoint |
| `system` | Internal event | session-id, component |
| `user` | Human input | session-id |

### Examples
```
[2026-01-09T10:00:00Z][event:chrome][airbnb.com/s/Paris] clicked [Search], 24 listings loaded
[2026-01-09T10:00:05Z][event:bash][git-status] clean working directory
[2026-01-09T10:00:10Z][event:file][src/config.json] modified
[2026-01-09T10:00:15Z][event:api][api.stripe.com/charges] 200 OK, charge_id=ch_123
[2026-01-09T10:00:20Z][event:system][abc123] session started
[2026-01-09T10:00:25Z][event:user][abc123] captcha solved: boats
```

---

## Agents

### Format
```
[2026-01-09T10:00:00Z][agent:status][session-id] output | need: criteria
```

| Field | Description | Example |
|-------|-------------|---------|
| `timestamp` | ISO 8601 UTC | `2026-01-09T10:00:00Z` |
| `agent:status` | Type + lifecycle | `agent:start`, `agent:finish` |
| `session-id` | Claude Code session | `abc123` |
| `output` | Description/result | `Booked flight, confirmation #XYZ` |
| `need:` | Success criteria or blocker | `confirmation number` |

### Statuses

| Status | Meaning | Set By | Next |
|--------|---------|--------|------|
| `start` | Project created | User/System | → active |
| `active` | Agent working | Agent | → finish |
| `finish` | Agent thinks done | Agent | → verified/retry |
| `verified` | Success confirmed | Level 2 | (terminal) |
| `retry` | Try again | Level 2 | → active |
| `failed` | Cannot proceed | Agent/Level 2 | (terminal or → retry) |

### Lifecycle
```
start → active → finish → verified ✓
                    ↓
                  retry → active → finish → verified ✓
                    ↓
                  failed → (user input) → retry → active ...
```

### Examples
```
# Happy path
[2026-01-09T10:00:00Z][agent:start][abc123] Book Tokyo flights under $500 | need: confirmation number
[2026-01-09T10:00:05Z][agent:active][abc123] searching flights
[2026-01-09T10:15:00Z][agent:finish][abc123] Booked JAL $450, confirmation #XYZ789
[2026-01-09T10:15:30Z][agent:verified][abc123] success criteria met

# Retry path
[2026-01-09T11:00:00Z][agent:start][def456] Find Airbnb in Paris | need: listing URL with price
[2026-01-09T11:00:05Z][agent:active][def456] searching listings
[2026-01-09T11:10:00Z][agent:finish][def456] Found listings but no prices shown
[2026-01-09T11:10:30Z][agent:retry][def456] prices not in output, try clicking into listing
[2026-01-09T11:10:35Z][agent:active][def456] clicking into first listing
[2026-01-09T11:15:00Z][agent:finish][def456] Listing: airbnb.com/rooms/123, $150/night
[2026-01-09T11:15:30Z][agent:verified][def456] success criteria met

# Escalation path
[2026-01-09T12:00:00Z][agent:start][ghi789] Book restaurant reservation | need: confirmation email
[2026-01-09T12:00:05Z][agent:active][ghi789] navigating to OpenTable
[2026-01-09T12:05:00Z][agent:failed][ghi789] captcha appeared | need: solve captcha
[2026-01-09T12:05:01Z][event:system][ghi789] Solve captcha at opentable.com/captcha
[2026-01-09T12:10:00Z][event:user][ghi789] captcha solved
[2026-01-09T12:10:05Z][agent:retry][ghi789] user solved captcha, continuing
[2026-01-09T12:10:10Z][agent:active][ghi789] resuming reservation flow
[2026-01-09T12:15:00Z][agent:finish][ghi789] Reserved 7pm at Chez Claude, confirmation sent
[2026-01-09T12:15:30Z][agent:verified][ghi789] success criteria met
```

---

## Read Marker

Separates read from unread entries.

```
[2026-01-09T09:00:00Z][event:chrome][example.com] page loaded
[2026-01-09T09:30:00Z][agent:active][abc123] working
[2026-01-09T09:30:30Z][event:system][manager-xyz] checked 2 events
=================READ-MARKER=================
[2026-01-09T10:00:00Z][event:chrome][example.com] clicked button  ← new
```

- **Above marker**: Already processed
- **Below marker**: New/unread
- Each `check` adds audit trail + new marker

---

## Supervisors

### Level 1: State Enforcer (Pure Code)

**Job**: world.log state = system state

| Log Says | System | Action |
|----------|--------|--------|
| Agent active | Not running | Restart |
| Agent not in log | Running | Kill orphan |

```bash
# Runs every N seconds
# No AI needed - pure rule-based
```

### Level 2: Intention Verifier (AI)

**Job**: Every agent → verified or failed

| Agent Status | Action |
|--------------|--------|
| `finish` | Verify output against `need:` criteria |
| `finish` + not verified | Retry with guidance |
| `finish` + max retries | Fail + escalate |
| `active` + stale | Poke with retry |
| `failed` + user input | Retry |

---

## Query Examples

```bash
# All chrome events
rg '\[event:chrome\]' world.log

# Events for specific site
rg '\[event:chrome\]\[airbnb\.com' world.log

# All agent abc123 entries
rg '\[abc123\]' world.log

# All active agents
rg '\[agent:active\]' world.log

# All failed agents
rg '\[agent:failed\]' world.log

# Agents awaiting verification
rg '\[agent:finish\]' world.log

# Human escalations
rg '\[event:user\]' world.log

# Events in last hour
rg '\[2026-01-09T10:' world.log
```

---

## Tool Commands

```bash
# Log event
claude-tools world event chrome "airbnb.com" "clicked Search"

# Log agent status
claude-tools world agent start abc123 "Book flights" --need "confirmation"
claude-tools world agent active abc123 "searching"
claude-tools world agent finish abc123 "Booked JAL $450"

# Check for new entries
claude-tools world check [agent-id]

# Query helpers
claude-tools world query active-agents
claude-tools world query pending-verification
```

---

## Value Proposition Alignment

| Promise | Mechanism |
|---------|-----------|
| **件件有着落** | Every agent tracked until verified/failed |
| **事事有回音** | User notified on success or escalation |
| **责任转移** | User declares once, system owns completion |
| **No silent failure** | Level 2 guarantees closure |

---

## File Location

```
claude-tools/world/
├── run.sh              # Entry point
├── world.log           # The log
├── README.md           # This spec
├── commands/           # Subcommands
└── supervisors/        # Level 1 + Level 2
```
