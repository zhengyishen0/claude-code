# 有谱 Proactive System Design

## Overview

The proactive system enables AI agents to work autonomously while maintaining human oversight. Core principle: **件件有着落，事事有回音** (nothing falls through, everything gets a response).

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         有谱 PROACTIVE SYSTEM                   │
│                                                                 │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐     │
│  │ TASK AGENTS │      │  world.log  │      │ SUPERVISORS │     │
│  │ (proactive) │ ───▶ │  (shared    │ ◀─── │ (reactive)  │     │
│  │             │      │   memory)   │      │             │     │
│  └─────────────┘      └─────────────┘      └─────────────┘     │
│        │                    │                     │             │
│        │                    ▼                     │             │
│        │              ┌──────────┐                │             │
│        │              │ TRIGGERS │                │             │
│        │              │ (events) │────────────────┘             │
│        │              └──────────┘                              │
│        │                    │                                   │
│        ▼                    ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                      SWIFT UI                            │   │
│  │                  (Spirit + Monitor)                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. World Log (Shared Memory)

Single source of truth. Append-only plain text.

**Format:**
```
# Events (facts, no tracking)
[timestamp][event:source][identifier] output

# Agents (projects, tracked lifecycle)
[timestamp][agent:status][session-id] output | need: criteria
```

**Event Sources:** chrome, bash, file, api, system, user

**Agent Statuses:** start, active, finish, verified, retry, failed

**Lifecycle:**
```
start → active → finish → verified ✓
                    ↓
                  retry → active → finish → verified ✓
                    ↓
                  failed → (human input) → retry → ...
```

### 2. Task Agents (Proactive)

Autonomous agents that perform work. They DRIVE the system.

**Characteristics:**
- Continuous session (maintains context)
- Proactively decide what to read/write
- Use world.log as a tool (not controlled by it)
- Own their actions and decisions

**Tools available to Task Agents:**
```
world.event(source, id, output)   # Log facts
world.agent(status, session, msg) # Log own status
world.check()                     # See new entries
world.query(type)                 # Query log
chrome.*                          # Browser actions
bash.*                            # Shell actions
```

**Example Task Agent Flow:**
```
1. Receive task: "Book Tokyo flight | need: confirmation number"
2. world.agent(start, "abc123", "Book Tokyo flight | need: confirmation number")
3. chrome.open("kayak.com")
4. world.event(chrome, "kayak.com", "opened flight search")
5. chrome.search("Tokyo flights")
6. world.event(chrome, "kayak.com", "found 15 flights")
7. ... (more actions)
8. world.agent(finish, "abc123", "Booked JAL $450, confirmation #XYZ789")
9. Exit (supervisor will verify)
```

### 3. Supervisors (Reactive)

Observers that ensure quality and handle failures. They RESPOND to the system.

**Model: Resume-Based One-Shot**
- Triggered by events (not always running)
- Resumes previous session (maintains context)
- No idle waiting (cost efficient)
- Full memory across triggers

```
Trigger → Resume session → Process → Sleep
             │
             └── Context preserved between triggers
```

#### Level 1 Supervisor (State Enforcement)

**Type:** Pure code (no LLM)
**Trigger:** Periodic (cron) or file watch
**Purpose:** Ensure log state = system state

**Checks:**
- Active agents have running processes
- No orphaned processes without log entries
- Timestamps are reasonable

**Actions:**
- Mark abandoned agents as failed
- Clean up orphaned processes
- Alert on anomalies

#### Level 2 Supervisor (Verification)

**Type:** LLM-powered (resume-based)
**Trigger:** Agent reaches `finish` status
**Purpose:** Verify output meets success criteria

**Input:**
```
Recent log entries (past few hours, trimmed):
[agent:start][abc123] Book Tokyo flight | need: confirmation number
[agent:active][abc123] searching flights
[event:chrome][kayak.com] found 15 flights
[agent:finish][abc123] Booked JAL $450, confirmation #XYZ789

Verify: Does finish output satisfy | need: criteria?
```

**Decisions:**
| Condition | Action |
|-----------|--------|
| Output matches need | → `verified` |
| Output incomplete, retry possible | → `retry` with guidance |
| Max retries (3) exceeded | → `failed` |
| Human input received | → `retry` with input |

**Session Continuity:**
```bash
SUPERVISOR_SESSION="supervisor-level2"

# Each trigger resumes the same session
claude --resume "$SUPERVISOR_SESSION" --message "
New entries since last check:
$(world check supervisor)

Verify any agents in 'finish' status.
"
```

### 4. Trigger System

Events that wake up supervisors.

**Trigger Types:**

| Trigger | Target | When |
|---------|--------|------|
| File watch | Level 2 | world.log changes |
| Cron (5 min) | Level 1 | Periodic state check |
| Cron (1 hour) | Timeout check | Detect stuck agents |
| Human respond | Level 2 | User provides input |

**Implementation:**
```bash
# File watcher trigger
fswatch -o world.log | while read; do
    world supervisor level2
done

# Cron trigger (in crontab)
*/5 * * * * world supervisor level1
0 * * * * world supervisor timeout-check
```

### 5. Timing/Timeout System

System-level checks (not supervisor logic).

**Timeout Rules:**
```
[agent:start] + 1 hour with no [agent:active] → Alert
[agent:active] + 2 hours with no [agent:finish] → Alert
[agent:failed] + 24 hours with no response → Escalate
```

**Implementation:**
```bash
# timeout-check.sh (cron job)
now=$(date +%s)

# Find agents stuck in start
grep "\[agent:start\]" world.log | while read line; do
    timestamp=$(extract_timestamp "$line")
    session=$(extract_session "$line")

    if (( now - timestamp > 3600 )); then
        if ! grep -q "\[agent:active\]\[$session\]" world.log; then
            world agent failed "$session" "Timeout: no activity after start"
        fi
    fi
done
```

### 6. Human-in-the-Loop

When supervisor marks agent as `failed`, human input is needed.

**Flow:**
```
[agent:failed][abc123] captcha required | need: solve captcha
                    │
                    ▼
            ┌──────────────┐
            │   SWIFT UI   │
            │              │
            │ Spirit nudge │
            │ "Need help"  │
            │              │
            │ [Input: ___] │
            └──────────────┘
                    │
                    ▼
world respond abc123 "captcha text: XKCD42"
                    │
                    ▼
[event:user][abc123] captcha text: XKCD42
                    │
                    ▼
            Level 2 Supervisor triggered
            → Sees user input
            → Marks for retry
                    │
                    ▼
[agent:retry][abc123] Retrying with user input: captcha text
```

## Data Flow Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   USER                                                          │
│     │                                                           │
│     │ "Book Tokyo flight"                                       │
│     ▼                                                           │
│   TASK AGENT (proactive, continuous)                            │
│     │                                                           │
│     │ world.agent(start, ...) ─────────────────┐                │
│     │ chrome.open(...) ───▶ world.event(...)   │                │
│     │ ... actions ...                          │                │
│     │ world.agent(finish, ...) ────────────────┤                │
│     ▼                                          ▼                │
│   EXITS                                   world.log             │
│                                               │                 │
│                                    ┌──────────┴──────────┐      │
│                                    ▼                     ▼      │
│                              File watcher            Cron       │
│                                    │                     │      │
│                                    ▼                     ▼      │
│                              Level 2              Level 1       │
│                              Supervisor           Supervisor    │
│                              (resume)             (one-shot)    │
│                                    │                            │
│                    ┌───────────────┼───────────────┐            │
│                    ▼               ▼               ▼            │
│                verified         retry           failed          │
│                    │               │               │            │
│                    ▼               ▼               ▼            │
│                  Done        Task Agent      SWIFT UI           │
│                              continues       "Need help"        │
│                                                   │             │
│                                                   ▼             │
│                                              User input         │
│                                                   │             │
│                                                   ▼             │
│                                            world.respond        │
│                                                   │             │
│                                                   ▼             │
│                                            Level 2 retry        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Swift UI Integration

### Reading World State

```swift
class WorldMonitor: ObservableObject {
    @Published var activeAgents: [Agent] = []
    @Published var pendingAgents: [Agent] = []  // finish, awaiting verification
    @Published var failedAgents: [Agent] = []   // need human input
    @Published var recentEvents: [Event] = []

    func refresh() {
        // Call: world query active
        // Call: world query pending
        // Call: world query failed
        // Call: world query recent 20
    }
}
```

### File Watching

```swift
class WorldLogWatcher {
    let fileURL = URL(fileURLWithPath: "path/to/world.log")
    var fileHandle: FileHandle?

    func startWatching() {
        // Use DispatchSource.makeFileSystemObjectSource
        // On change: notify UI + trigger supervisor
    }
}
```

### Spirit States

| World State | Spirit Behavior |
|-------------|-----------------|
| No active agents | Idle (soft glow) |
| Agents working | Pulse animation |
| Agent verified | Brief sparkle |
| Agent failed | Nudge out + "Need help" bubble |

### Human Response UI

```swift
struct FailedAgentView: View {
    let agent: Agent
    @State var response: String = ""

    var body: some View {
        VStack {
            Text(agent.sessionId)
            Text(agent.failureReason)  // from | need:
            TextField("Your response", text: $response)
            Button("Send") {
                // Call: world respond <session-id> <response>
            }
        }
    }
}
```

## Implementation Checklist

### Phase 1: Core (Done)
- [x] world.log format
- [x] event command
- [x] agent command
- [x] check command
- [x] query command
- [x] respond command
- [x] Level 1 supervisor (basic)
- [x] Level 2 supervisor (basic)

### Phase 2: Triggers
- [ ] File watcher for world.log
- [ ] Cron setup for Level 1
- [ ] Timeout check script
- [ ] Trigger → supervisor integration

### Phase 3: Resume-Based Supervisors
- [ ] Session management for Level 2
- [ ] Resume logic implementation
- [ ] Context trimming (recent hours only)
- [ ] Session persistence

### Phase 4: Swift UI
- [ ] Spirit floating window
- [ ] Edge-docking behavior
- [ ] WorldMonitor class
- [ ] File watcher integration
- [ ] Human response UI
- [ ] Agent status display

### Phase 5: Integration Test
- [ ] Full lifecycle test
- [ ] Happy path
- [ ] Retry path
- [ ] Human-in-loop path
- [ ] Timeout scenarios

## Key Design Decisions

1. **Plain text log** - grep-able, human readable, fast
2. **Resume-based supervisors** - context without idle waiting
3. **Task agents proactive** - they drive, world is their tool
4. **Supervisors reactive** - they respond to changes
5. **Timing at system level** - cron/scripts, not supervisor logic
6. **Log as memory** - if it's not logged, it didn't happen
