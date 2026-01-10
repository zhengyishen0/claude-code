# 有谱 Proactive System Design

## Overview

The proactive system enables AI agents to work autonomously while maintaining human oversight. Core principle: **件件有着落，事事有回音** (nothing falls through, everything gets a response).

## Three-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         有谱 PROACTIVE SYSTEM                           │
│                                                                         │
│  VOICE SYSTEM (always listening)                                        │
│         │                                                               │
│         ▼                                                               │
│    Transcription + Speaker ID                                           │
│         │                                                               │
│         ▼                                                               │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  LEVEL 3: SPIRIT / INTENTION AGENT                              │   │
│  │  (proactive, continuous, autonomous)                            │   │
│  │                                                                 │   │
│  │  "The Mind" - Detects intent, decides what to do                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│         │                                                               │
│         │ spawns                                                        │
│         ▼                                                               │
│    TASK AGENTS ───────────────▶ world.log ◀─────────────┐              │
│                                     │                    │              │
│              ┌──────────────────────┴────────────────────┤              │
│              ▼                                           ▼              │
│  ┌───────────────────────────┐           ┌───────────────────────────┐ │
│  │  LEVEL 2: VERIFIER        │           │  LEVEL 1: SYSTEM KEEPER   │ │
│  │  (reactive, resume-based) │           │  (reactive, pure code)    │ │
│  │                           │           │                           │ │
│  │  "Quality Assurance"      │           │  "Health Monitor"         │ │
│  │  Verify, retry, escalate  │           │  Process, logs, timeouts  │ │
│  └───────────────────────────┘           └───────────────────────────┘ │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                          SWIFT UI                                │   │
│  │                     (Spirit + Monitor)                           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Level Comparison

| Level | Name | Mode | Purpose | Implementation |
|-------|------|------|---------|----------------|
| **L1** | System Keeper | Reactive, pure code | Keep system healthy | Shell scripts, cron |
| **L2** | Verifier | Reactive, resume-based | Ensure quality | LLM, triggered by log |
| **L3** | Spirit | Proactive, continuous | Detect intent, start work | LLM, always running |

**Key insight:** Level 3 is the "mind" that DRIVES action. Levels 1 & 2 are the "immune system" that ensures quality.

## Components

### Level 3: Spirit / Intention Agent

The proactive brain of the system. Always running, always watching.

**Inputs:**
```
┌─────────────────────────────────────────────────────────────────┐
│  SPIRIT INPUTS                                                  │
│                                                                 │
│  1. TRANSCRIPTION STREAM                                        │
│     └── What user and others are saying (from voice system)     │
│                                                                 │
│  2. WORLD.LOG                                                   │
│     └── What's happening in the system (events, agents)         │
│                                                                 │
│  3. ENVIRONMENT                                                 │
│     └── Time, calendar, location, system state                  │
│                                                                 │
│  4. USER HISTORY                                                │
│     └── Patterns, preferences, past interactions                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Decision Logic:**
```
┌─────────────────────────────────────────────────────────────────┐
│  SPIRIT DECISIONS                                               │
│                                                                 │
│  IF user says "remind me to..."                                 │
│     → Spawn reminder agent                                      │
│                                                                 │
│  IF user discussing flights with someone                        │
│     → Nudge: "Want me to search flights?"                       │
│                                                                 │
│  IF calendar shows meeting in 15 min                            │
│     → Spawn meeting prep agent                                  │
│                                                                 │
│  IF nothing actionable                                          │
│     → Stay quiet (presence without intrusion)                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Outputs:**
- **Spawn task agent** - Start autonomous work
- **Nudge UI** - Ask user for confirmation before acting
- **Log observation** - Record insight for future reference
- **Stay quiet** - Most of the time, do nothing

**Characteristics:**
- Continuous session (always running)
- Maintains long-term context
- Proactive (initiates action)
- Conservative (asks before major actions)

### Level 2: Verifier

Ensures task agents complete work correctly. Reactive, resume-based.

**Type:** LLM-powered
**Mode:** Resume-based one-shot (context preserved, no idle waiting)
**Trigger:** Agent reaches `finish` status

**Process:**
```
Trigger (agent finishes)
    │
    ▼
Resume session (preserve context)
    │
    ▼
Read recent log entries
    │
    ▼
Compare output vs | need: criteria
    │
    ├── Match → verified ✓
    ├── Partial → retry with guidance
    └── Failed 3x → failed, escalate to user
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

### Level 1: System Keeper

Keeps the system healthy. Pure code, no LLM needed.

**Type:** Shell scripts
**Mode:** One-shot (cron triggered)
**Trigger:** Periodic (every 5 minutes)

**Checks:**
- Active agents have running processes
- No orphaned processes without log entries
- Timestamps are reasonable (no stuck agents)
- Log file is not corrupted

**Actions:**
- Mark abandoned agents as failed
- Clean up orphaned processes
- Alert on anomalies
- Timeout stuck agents

**Timeout Rules:**
```
[agent:start] + 1 hour with no [agent:active] → Mark failed
[agent:active] + 2 hours with no [agent:finish] → Mark failed
[agent:failed] + 24 hours with no response → Escalate
```

### World Log (Shared Memory)

Single source of truth. Append-only plain text.

**Format:**
```
# Events (facts, no tracking)
[timestamp][event:source][identifier] output

# Agents (projects, tracked lifecycle)
[timestamp][agent:status][session-id] output | need: criteria
```

**Event Sources:** chrome, bash, file, api, system, user, voice

**Agent Statuses:** start, active, finish, verified, retry, failed

**Lifecycle:**
```
start → active → finish → verified ✓
                    ↓
                  retry → active → finish → verified ✓
                    ↓
                  failed → (human input) → retry → ...
```

### Task Agents

Workers that perform actual tasks. Spawned by Level 3 Spirit.

**Characteristics:**
- Continuous session (for complex tasks)
- Proactively decide what to read/write
- Use world.log as a tool
- Own their actions and decisions

**Tools available:**
```
world.event(source, id, output)   # Log facts
world.agent(status, session, msg) # Log own status
world.check()                     # See new entries
world.query(type)                 # Query log
chrome.*                          # Browser actions
bash.*                            # Shell actions
```

**Example Flow:**
```
1. Spirit spawns agent: "Book Tokyo flight | need: confirmation number"
2. world.agent(start, "abc123", "Book Tokyo flight | need: confirmation number")
3. chrome.open("kayak.com")
4. world.event(chrome, "kayak.com", "opened flight search")
5. ... (more actions)
6. world.agent(finish, "abc123", "Booked JAL $450, confirmation #XYZ789")
7. Exit (Level 2 will verify)
```

## Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  VOICE SYSTEM                                                           │
│       │                                                                 │
│       │ transcription + speaker ID                                      │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  LEVEL 3: SPIRIT (continuous)                                   │   │
│  │                                                                 │   │
│  │  Inputs: transcription, world.log, environment                  │   │
│  │  Decides: "User wants to book a flight"                         │   │
│  │  Action: Spawn task agent                                       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       │ spawns                                                          │
│       ▼                                                                 │
│  TASK AGENT (continuous for task duration)                              │
│       │                                                                 │
│       │ world.agent(start, ...) ─────────────────┐                      │
│       │ chrome.open(...) ───▶ world.event(...)   │                      │
│       │ ... actions ...                          │                      │
│       │ world.agent(finish, ...) ────────────────┤                      │
│       ▼                                          ▼                      │
│     EXITS                                   world.log                   │
│                                                 │                       │
│                              ┌──────────────────┴──────────────────┐    │
│                              ▼                                     ▼    │
│                        File watcher                             Cron    │
│                              │                                     │    │
│                              ▼                                     ▼    │
│  ┌───────────────────────────────────┐   ┌───────────────────────────┐ │
│  │  LEVEL 2: VERIFIER (resume)       │   │  LEVEL 1: SYSTEM (code)   │ │
│  │                                   │   │                           │ │
│  │  Verify finish vs need            │   │  Check health             │ │
│  │  → verified / retry / failed      │   │  → timeouts, orphans      │ │
│  └───────────────────────────────────┘   └───────────────────────────┘ │
│                  │                                                      │
│       ┌──────────┼──────────┐                                          │
│       ▼          ▼          ▼                                          │
│   verified    retry      failed                                        │
│       │          │          │                                          │
│       ▼          ▼          ▼                                          │
│     Done    Task Agent   SWIFT UI                                      │
│             continues    "Need help"                                   │
│                              │                                          │
│                              ▼                                          │
│                         User input                                      │
│                              │                                          │
│                              ▼                                          │
│                       world.respond                                     │
│                              │                                          │
│                              ▼                                          │
│                       Level 2 retry                                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Human-in-the-Loop

When Level 2 marks agent as `failed`, Spirit notifies user.

**Flow:**
```
[agent:failed][abc123] captcha required | need: solve captcha
                    │
                    ▼
            Spirit detects failure
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
            Level 2 triggered
            → Sees user input
            → Marks for retry
```

## Swift UI Integration

### Spirit Visual States

| System State | Spirit Behavior |
|--------------|-----------------|
| Idle (no activity) | Soft breathing glow, edge-docked |
| Listening (processing speech) | Gentle pulse |
| Agents working | Orbit animation |
| Needs attention (failed agent) | Nudge out + bubble |
| Task completed | Brief sparkle |

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

### Spirit as Level 3 Host

```swift
class SpiritAgent: ObservableObject {
    // Continuous LLM session
    var sessionId: String?

    // Inputs
    var transcriptionStream: AsyncStream<Transcription>
    var worldLogWatcher: WorldLogWatcher

    func run() async {
        // Always running loop
        for await transcription in transcriptionStream {
            // Feed to Level 3 agent
            let decision = await processWithLLM(transcription)

            switch decision {
            case .spawnAgent(let task):
                spawnTaskAgent(task)
            case .nudge(let message):
                showNudgeBubble(message)
            case .observe(let note):
                logObservation(note)
            case .nothing:
                continue
            }
        }
    }
}
```

## Implementation Progress

### Level 1: System Keeper
| Item | Status |
|------|--------|
| Basic state enforcement script | ✅ Done |
| Process health check | ✅ Done |
| Timeout detection | ⬜ Not started |
| Cron integration | ⬜ Not started |
| Orphan cleanup | ⬜ Not started |

### Level 2: Verifier
| Item | Status |
|------|--------|
| Basic verification logic | ✅ Done |
| Retry handling | ✅ Done |
| Failure escalation | ✅ Done |
| Human input processing | ✅ Done |
| Resume-based sessions | ⬜ Not started |
| File watcher trigger | ⬜ Not started |

### Level 3: Spirit
| Item | Status |
|------|--------|
| Design specification | ✅ Done (this doc) |
| Continuous session management | ⬜ Not started |
| Transcription integration | ⬜ Not started |
| Intent detection | ⬜ Not started |
| Task agent spawning | ⬜ Not started |
| Conservative nudging | ⬜ Not started |

### World Log
| Item | Status |
|------|--------|
| Log format | ✅ Done |
| Event command | ✅ Done |
| Agent command | ✅ Done |
| Check command | ✅ Done |
| Query command | ✅ Done |
| Respond command | ✅ Done |

### Swift UI
| Item | Status |
|------|--------|
| Spirit floating window | ⬜ Not started |
| Edge-docking behavior | ⬜ Not started |
| WorldMonitor class | ⬜ Not started |
| File watcher integration | ⬜ Not started |
| Human response UI | ⬜ Not started |
| Agent status display | ⬜ Not started |

### Integration
| Item | Status |
|------|--------|
| Voice → Spirit pipeline | ⬜ Not started |
| Spirit → Task Agent spawning | ⬜ Not started |
| Task Agent → World Log | ⬜ Not started |
| World Log → Level 2 trigger | ⬜ Not started |
| Full lifecycle test | ⬜ Not started |

## Key Design Decisions

1. **Three levels, clear responsibilities**
   - L3: Mind (proactive, decides)
   - L2: Quality (reactive, verifies)
   - L1: Health (reactive, monitors)

2. **Level 3 is continuous, Levels 1 & 2 are triggered**
   - Spirit always runs (watching, listening)
   - Supervisors wake on events (efficient)

3. **Resume-based for Level 2**
   - Context preserved across triggers
   - No idle waiting (cost efficient)

4. **Plain text log**
   - grep-able, human readable, fast
   - Single source of truth

5. **Conservative proactivity**
   - Spirit nudges before major actions
   - User stays in control

6. **Log as memory**
   - If it's not logged, it didn't happen
   - Enables resume-based operation
