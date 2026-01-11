# 有谱 Proactive System Design

## Overview

The proactive system enables AI agents to work autonomously while maintaining human oversight. Core principle: **件件有着落，事事有回音** (nothing falls through, everything gets a response).

## The Pipeline: World.log as Single Source of Truth

Everything flows through **world.log**. The pipeline stages are not separate systems—they are **views/filters** on the same log.

### The Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        WORLD.LOG = SINGLE SOURCE OF TRUTH                   │
│                                                                             │
│   NOTE              TASK               VERIFIED           DELIVER           │
│   ────              ────               ────────           ───────           │
│                                                                             │
│   [note:*]    ───▶  [agent:start]  ───▶  [agent:verified]  ───▶  [deliver:*]│
│                     [agent:active]                                          │
│                     [agent:finish]                                          │
│                           │                                                 │
│                           ▼                                                 │
│                     L2 Verifier                                             │
│                                                                             │
│   ─────────────────────────────────────────────────────────────────────────│
│                                                                             │
│   INBOX = filter(verified AND NOT delivered)                                │
│                                                                             │
│   Not a separate log entry—just a query on the log.                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key insight:** Inbox is not a stage that needs logging. It's a **filter/view** on verified tasks that haven't been delivered yet.

### World.log Entry Types

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ENTRY TYPES IN WORLD.LOG                                                   │
│                                                                             │
│  [note:source][topic] observation                                           │
│  └── Entry point. Someone observed something worth remembering.             │
│                                                                             │
│  [agent:start][id] task | note: topic | need: criteria                      │
│  [agent:active][id] progress update                                         │
│  [agent:finish][id] summary | link: /path/to/details                        │
│  [agent:verified][id] ✓                                                     │
│  [agent:retry][id] guidance                                                 │
│  [agent:failed][id] reason | need: human input                              │
│  └── Task lifecycle. Links back to original note via `note: topic`.         │
│                                                                             │
│  [event:source][context] what happened                                      │
│  └── Facts from tools (chrome, bash, etc).                                  │
│                                                                             │
│  [deliver:mode][id] silent|nudge|interrupt                                  │
│  └── Delivery decision. Marks task as "delivered" for inbox filter.         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Pipeline as Queries

| "Stage" | Query | Returns |
|---------|-------|---------|
| **Notes** | `grep "\[note:"` | All observations |
| **Active work** | `grep "\[agent:start\]\|\[agent:active\]"` | Tasks in progress |
| **Finished** | `grep "\[agent:finish\]"` | Completed work |
| **Inbox** | verified AND NOT delivered | Ready to surface |
| **Delivered** | `grep "\[deliver:"` | What user has seen |

### Example Flow

```
1. Spirit hears: "I'm thinking about Tokyo next month"
   → [note:voice][tokyo-trip] User interested in visiting Tokyo next month

2. Spirit decides this is worth researching
   → [agent:start][abc123] Research Tokyo | note: tokyo-trip | need: flights, hotels

3. Agent works, logs progress
   → [event:chrome][abc123] opened kayak.com
   → [agent:finish][abc123] Found 3 flights $450-$680 | link: /results/abc123.md

4. L2 Verifier checks output vs | need:
   → [agent:verified][abc123] ✓

5. INBOX query: verified + not delivered
   → Returns: abc123 (tokyo research)

6. Spirit decides delivery mode (time-sensitive? consequence?)
   → [deliver:nudge][abc123] "I found Tokyo flight options"

7. Client shows nudge to user
```

### Delivery Modes

Once something is in the Inbox, Spirit decides HOW to deliver:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DELIVERY MODES                                     │
│                                                                             │
│        SILENT              NUDGE               INTERRUPT                    │
│        ──────              ─────               ─────────                    │
│                                                                             │
│     Wait for user       Gentle mention        Full alert                    │
│     to ask              when idle             demand attention              │
│                                                                             │
│     "I have info        "By the way,          "Your flight                  │
│      if you want"        I found..."           boards NOW!"                 │
│                                                                             │
│     User must ask       User can ignore       User must acknowledge         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### The Interrupt Formula

Inspired by iOS Time-Sensitive notifications:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│                    INTERRUPT = TIME-SENSITIVE + CONSEQUENCE                 │
│                                                                             │
│   Both conditions must be true:                                             │
│   1. Time-sensitive: Opportunity will be lost soon                          │
│   2. Consequence: User will suffer if they miss it                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Examples:**

| Situation | Time-Sensitive? | Consequence? | Result |
|-----------|-----------------|--------------|--------|
| "Flight boards in 10 min" | Yes | Miss flight | **INTERRUPT** |
| "Sale ends tonight" | Yes | Save money (minor) | Nudge |
| "You usually call mom Sundays" | No | - | Nudge |
| "Uber is outside" | Yes | Driver leaves | **INTERRUPT** |
| "Flash sale on random product" | Yes | Nothing (didn't ask) | Silent/Ignore |
| "Research on Tokyo ready" | No | - | Silent or Nudge |

### Decision Tree

```
Something in Inbox ready for delivery
              │
              ▼
    Is it time-sensitive?
    ├── No ──────────────────────────────────────┐
    │                                            │
    └── Yes                                      │
         │                                       │
         ▼                                       │
    Will user suffer if missed?                  │
    ├── No ─────────────────────┐                │
    │                           │                │
    └── Yes                     │                │
         │                      │                │
         ▼                      ▼                ▼
    ┌─────────┐           ┌─────────┐      ┌─────────┐
    │INTERRUPT│           │  NUDGE  │      │ SILENT  │
    └─────────┘           └─────────┘      └─────────┘
         │                      │                │
         ▼                      ▼                ▼
    Must                  Can ignore        Wait for
    acknowledge           when idle         user to ask
```

## Three-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         有谱 PROACTIVE SYSTEM                               │
│                                                                             │
│  VOICE SYSTEM (always listening)                                            │
│         │                                                                   │
│         ▼                                                                   │
│    Transcription + Speaker ID                                               │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  LEVEL 3: SPIRIT (The Butler)                                       │   │
│  │  ════════════════════════════                                       │   │
│  │                                                                     │   │
│  │  Pipeline: Note → Background → Inbox → Deliver                      │   │
│  │  Delivery: Silent | Nudge | Interrupt                               │   │
│  │                                                                     │   │
│  │  Always listening. Always thinking. Acts at the right moment.       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│         │                                                                   │
│         │ spawns                                                            │
│         ▼                                                                   │
│    TASK AGENTS ───────────────▶ world.log ◀─────────────┐                  │
│                                     │                    │                  │
│              ┌──────────────────────┴────────────────────┤                  │
│              ▼                                           ▼                  │
│  ┌───────────────────────────┐           ┌───────────────────────────┐     │
│  │  LEVEL 2: VERIFIER        │           │  LEVEL 1: SYSTEM KEEPER   │     │
│  │  (reactive, resume-based) │           │  (reactive, pure code)    │     │
│  │                           │           │                           │     │
│  │  "Quality Assurance"      │           │  "Health Monitor"         │     │
│  │  Verify, retry, escalate  │           │  Process, logs, timeouts  │     │
│  └───────────────────────────┘           └───────────────────────────┘     │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                          SWIFT UI                                   │   │
│  │                     (Spirit + Monitor)                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Level Comparison

| Level | Name | Mode | Purpose | Implementation |
|-------|------|------|---------|----------------|
| **L1** | System Keeper | Reactive, pure code | Keep system healthy | Shell scripts, cron |
| **L2** | Verifier | Reactive, resume-based | Ensure quality | LLM, triggered by log |
| **L3** | Spirit | Proactive, continuous | Orchestrate everything | LLM, always running |

**Key insight:** Level 3 is the "mind" that DRIVES action. Levels 1 & 2 are the "immune system" that ensures quality.

## Spirit Details

### Inputs

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

### Pipeline in Action

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  EXAMPLE: User mentions "thinking about Tokyo next month"                   │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ NOTE                                                                 │  │
│  │ Spirit hears: "I'm thinking about visiting Tokyo next month"         │  │
│  │ Records: user_interest = {destination: Tokyo, timeframe: next_month} │  │
│  └────────────────────────────┬─────────────────────────────────────────┘  │
│                               │                                             │
│                               ▼                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ BACKGROUND                                                           │  │
│  │ Spirit spawns silent research:                                       │  │
│  │ - Check flight prices (Kayak, Google Flights)                        │  │
│  │ - Weather in Tokyo next month                                        │  │
│  │ - User's calendar availability                                       │  │
│  │ - Hotel options near places user has mentioned liking                │  │
│  └────────────────────────────┬─────────────────────────────────────────┘  │
│                               │                                             │
│                               ▼                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ INBOX                                                                │  │
│  │ Research complete:                                                   │  │
│  │ - 3 flight options ($450-$680)                                       │  │
│  │ - Weather: mild, cherry blossom season                               │  │
│  │ - Calendar: March 15-22 is clear                                     │  │
│  │ - Hotels: 5 options in Shibuya                                       │  │
│  └────────────────────────────┬─────────────────────────────────────────┘  │
│                               │                                             │
│                               ▼                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ DELIVER: Which mode?                                                 │  │
│  │                                                                      │  │
│  │ Time-sensitive? No (user said "next month")                          │  │
│  │ Consequence if missed? No                                            │  │
│  │                                                                      │  │
│  │ Decision: NUDGE or SILENT (based on user's current state)            │  │
│  │                                                                      │  │
│  │ - If user is busy → SILENT (wait for "what about Tokyo?")            │  │
│  │ - If user is idle → NUDGE ("I found some Tokyo info if interested")  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Interrupt Examples

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  WHEN TO INTERRUPT                                                          │
│                                                                             │
│  ✓ INTERRUPT (time-sensitive + consequence)                                 │
│  ├── "Your flight boards in 10 minutes"                                     │
│  ├── "Uber driver is outside"                                               │
│  ├── "Meeting starts in 5 minutes, you're not dressed"                      │
│  ├── "Mom is calling" (implicit: she'll hang up)                            │
│  └── "Server is down, customers affected"                                   │
│                                                                             │
│  ✗ DON'T INTERRUPT (time-sensitive but no real consequence)                 │
│  ├── "Flash sale ends in 1 hour" (you didn't ask for this)                  │
│  ├── "New episode just released" (can watch later)                          │
│  └── "Stock price moved 2%" (unless you asked to be notified)               │
│                                                                             │
│  ✓ NUDGE (helpful, not urgent)                                              │
│  ├── "You usually call mom on Sundays"                                      │
│  ├── "I found the restaurant you mentioned"                                 │
│  ├── "Your package was delivered"                                           │
│  └── "Research on Tokyo is ready"                                           │
│                                                                             │
│  ✓ SILENT (available but not surfaced)                                      │
│  ├── Background research user didn't explicitly ask for                     │
│  ├── Monitoring results (nothing noteworthy)                                │
│  └── Context that might be useful later                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Level 2: Verifier

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
    └── Failed 3x → failed, escalate to Spirit
```

## Level 1: System Keeper

Keeps the system healthy. Pure code, no LLM needed.

**Type:** Shell scripts
**Mode:** One-shot (cron triggered)
**Trigger:** Periodic (every 5 minutes)

**Checks:**
- Active agents have running processes
- No orphaned processes without log entries
- Timestamps are reasonable (no stuck agents)
- Log file is not corrupted

**Timeout Rules:**
```
[agent:start] + 1 hour with no [agent:active] → Mark failed
[agent:active] + 2 hours with no [agent:finish] → Mark failed
[agent:failed] + 24 hours with no response → Escalate
```

## World Log (Shared Memory)

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

## Swift UI Integration

### Spirit Visual States

| Pipeline Stage | Spirit Behavior |
|----------------|-----------------|
| Idle (noting) | Soft breathing glow, edge-docked |
| Background (working) | Gentle orbit animation |
| Inbox (ready) | Subtle indicator dot |
| Nudge (delivering) | Nudge out + speech bubble |
| Interrupt (urgent) | Full emergence + sound + persistent |

### Delivery Mode UI

| Mode | Visual | Audio | Persistence |
|------|--------|-------|-------------|
| **Silent** | None (available on demand) | None | In Spirit's memory |
| **Nudge** | Speech bubble, auto-dismiss | Optional soft chime | Dismissable |
| **Interrupt** | Full modal, can't dismiss easily | Alert sound | Must acknowledge |

### Spirit State Machine

```swift
enum PipelineStage {
    case noting         // Observing, remembering
    case background     // Working silently
    case inbox          // Output ready
    case delivering     // Showing to user
}

enum DeliveryMode {
    case silent         // Wait for user to ask
    case nudge          // Gentle, ignorable
    case interrupt      // Urgent, must acknowledge
}

struct InboxItem {
    let content: String
    let source: BackgroundTask
    let timeSensitive: Bool
    let consequenceIfMissed: Bool

    var deliveryMode: DeliveryMode {
        if timeSensitive && consequenceIfMissed {
            return .interrupt
        } else if shouldProactivelySurface {
            return .nudge
        } else {
            return .silent
        }
    }
}
```

## Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  VOICE SYSTEM                                                               │
│       │                                                                     │
│       │ transcription + speaker ID                                          │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  LEVEL 3: SPIRIT                                                    │   │
│  │                                                                     │   │
│  │  [NOTE] ──▶ [BACKGROUND] ──▶ [INBOX] ──▶ [DELIVER]                  │   │
│  │                  │                           │                      │   │
│  │                  │ spawns                    │                      │   │
│  │                  ▼                           ▼                      │   │
│  │            Task Agents                  Silent/Nudge/Int            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                         │                           │
│       │ world.agent(start, ...)                 │                           │
│       ▼                                         ▼                           │
│  TASK AGENT                               SWIFT UI                          │
│       │                                   (shows to user)                   │
│       │ world.agent(finish, ...)                                            │
│       ▼                                                                     │
│  world.log ◀────────────────────────────────────────────────┐              │
│       │                                                      │              │
│       ├──────────────────────┬───────────────────────────────┤              │
│       ▼                      ▼                               │              │
│  File watcher              Cron                              │              │
│       │                      │                               │              │
│       ▼                      ▼                               │              │
│  ┌─────────────────┐   ┌─────────────────┐                   │              │
│  │ LEVEL 2         │   │ LEVEL 1         │                   │              │
│  │ Verifier        │   │ System Keeper   │                   │              │
│  │                 │   │                 │                   │              │
│  │ verified/retry/ │   │ health checks   │                   │              │
│  │ failed          │   │ timeouts        │                   │              │
│  └────────┬────────┘   └─────────────────┘                   │              │
│           │                                                   │              │
│           └───────────────────────────────────────────────────┘              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Design Principles

### 1. World.log is the Single Source of Truth

Everything goes to world.log:
- Notes, tasks, events, delivery decisions—all in one place
- Pipeline "stages" are queries/filters, not separate systems
- Spirit reconstructs state from log on startup
- No separate state files needed

### 2. Pipeline Stages Stack

Note → Task → Verified → Deliver is a natural flow:
- Everything starts with a note
- Some notes become tasks
- Verified tasks enter the inbox (a filter, not a log entry)
- Deliver is the decision point

### 3. Interrupt = Time-Sensitive + Consequence

Clear, implementable rule inspired by iOS:
- Both conditions must be true
- LLM can evaluate these independently
- Prevents notification spam

### 4. Inbox is a View, Not a Stage

Inbox = `verified AND NOT delivered`:
- No need to log "inbox" entries
- Just query the log for verified tasks without delivery entries
- Keeps the log clean and non-redundant

### 5. Conservative by Default

When in doubt:
- Silent > Nudge > Interrupt
- User attention is sacred
- Better to have info ready than to interrupt unnecessarily

### 6. 件件有着落 (Nothing Falls Through)

Every observed item enters the pipeline:
- Even if it stays at NOTE forever
- Even if it's SILENT and never surfaced
- The log remembers, so the user doesn't have to

## Client-Cloud Architecture

### The Split

The system is divided into a **thin client** (Swift app) and **cloud compute** (containers):

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CLIENT (Swift App)                                   │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  I/O ONLY - No business logic                                         │ │
│  │                                                                       │ │
│  │  CAPTURE:                        DISPLAY:                             │ │
│  │  • Voice → transcription         • Spirit UI (blob animation)         │ │
│  │  • Environment (time, location)  • Nudge bubbles                      │ │
│  │  • Calendar events               • Interrupt modals                   │ │
│  │  • User taps/responses           • TTS playback                       │ │
│  │                                                                       │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│         │ send                                          ▲ receive          │
│         ▼                                               │                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                        CLOUD (Apple Container)                              │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  ALL COMPUTE                                                          │ │
│  │                                                                       │ │
│  │  • Spirit (L3) - continuous LLM session                               │ │
│  │  • Task Agents - spawned workers                                      │ │
│  │  • Verifier (L2) - quality assurance                                  │ │
│  │  • System Keeper (L1) - health monitor                                │ │
│  │  • World.log - shared memory                                          │ │
│  │  • Tools: chrome, worktree, bash                                      │ │
│  │                                                                       │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### What Lives Where

| Component | Location | Why |
|-----------|----------|-----|
| Voice capture | Client | Hardware access, low latency |
| Transcription | Client | On-device ML (Whisper) |
| Speaker ID | Client | On-device ML |
| Spirit (L3) | Cloud | LLM compute, continuous session |
| Task Agents | Cloud | Need tools (chrome, git) |
| World.log | Cloud | Shared state for agents |
| L1/L2 Supervisors | Cloud | Monitor world.log |
| Spirit UI | Client | Display, animation |
| Delivery UI | Client | Nudge/Interrupt display |

### World.log Contains Everything

**Everything goes to world.log.** Spirit's notes, task progress, delivery decisions—all in one place.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  WORLD.LOG (single source of truth)                                         │
│                                                                             │
│  [note:voice][tokyo-trip] User interested in Tokyo next month               │
│  [agent:start][abc123] Research Tokyo | note: tokyo-trip | need: flights    │
│  [event:chrome][abc123] opened kayak.com                                    │
│  [agent:finish][abc123] Found 3 flights $450-$680 | link: /results/abc123   │
│  [agent:verified][abc123] ✓                                                 │
│  [deliver:nudge][abc123] "I found Tokyo flight options"                     │
│                                                                             │
│  Pipeline "stages" are just QUERIES on this log:                            │
│  • Notes = grep [note:                                                      │
│  • Active = grep [agent:start] or [agent:active]                            │
│  • Inbox = verified AND NOT delivered                                       │
│  • Delivered = grep [deliver:                                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**No separate Spirit state file needed.** Spirit reconstructs its state from the log on startup.

### Client-Cloud Protocol

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CLIENT → CLOUD (WebSocket)                                                 │
│                                                                             │
│  1. Transcription stream (continuous while speaking)                        │
│     {type: "transcription", speaker: "user", text: "...", ts: ...}          │
│                                                                             │
│  2. Environment updates (periodic, ~1/min or on change)                     │
│     {type: "environment", time: "...", location: "...", calendar: [...]}    │
│                                                                             │
│  3. User responses (on interaction)                                         │
│     {type: "response", item_id: "...", action: "dismiss|expand|confirm"}    │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  CLOUD → CLIENT (WebSocket)                                                 │
│                                                                             │
│  1. Delivery payloads                                                       │
│     {                                                                       │
│       type: "deliver",                                                      │
│       mode: "silent|nudge|interrupt",                                       │
│       id: "item_id",                                                        │
│       preview: "I found Tokyo info...",                                     │
│       full: "..." // sent on expand                                         │
│     }                                                                       │
│                                                                             │
│  2. Spirit state (for UI animation)                                         │
│     {type: "state", stage: "noting|background|inbox", agents: 3}            │
│                                                                             │
│  3. Voice output                                                            │
│     {type: "speak", text: "...", priority: "normal|urgent"}                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Full Data Flow with Client-Cloud

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│                                                                                   │
│  CLIENT                              │            CLOUD                           │
│  ──────                              │            ─────                           │
│                                      │                                            │
│  ┌──────────────┐                    │                                            │
│  │ Microphone   │                    │                                            │
│  └──────┬───────┘                    │                                            │
│         │ audio                      │                                            │
│         ▼                            │                                            │
│  ┌──────────────┐                    │                                            │
│  │ Whisper      │                    │                                            │
│  │ (on-device)  │                    │                                            │
│  └──────┬───────┘                    │                                            │
│         │ text                       │                                            │
│         ▼                            │                                            │
│  ┌──────────────┐  transcription     │   ┌────────────────────────────────────┐  │
│  │ Speaker ID   │ ─────────────────────▶ │ SPIRIT (L3)                        │  │
│  │ (on-device)  │                    │   │                                    │  │
│  └──────────────┘                    │   │ [NOTE] "User wants Tokyo trip"     │  │
│                                      │   │    │                               │  │
│  ┌──────────────┐  environment       │   │    ▼                               │  │
│  │ Calendar,    │ ─────────────────────▶ │ [BACKGROUND] spawn agent           │  │
│  │ Location     │                    │   │    │                               │  │
│  └──────────────┘                    │   └────┼───────────────────────────────┘  │
│                                      │        │                                   │
│                                      │        │ spawns                            │
│                                      │        ▼                                   │
│                                      │   ┌────────────────────────────────────┐  │
│                                      │   │ TASK AGENT                         │  │
│                                      │   │                                    │  │
│                                      │   │ world.agent(start, "abc123", ...)  │  │
│                                      │   │ chrome.open("kayak.com")           │  │
│                                      │   │ world.event(chrome, ...)           │  │
│                                      │   │ world.agent(finish, "abc123", ...) │  │
│                                      │   └────────────────┬───────────────────┘  │
│                                      │                    │                       │
│                                      │                    ▼                       │
│                                      │              ┌──────────┐                  │
│                                      │              │world.log │                  │
│                                      │              └────┬─────┘                  │
│                                      │                   │                        │
│                                      │        ┌──────────┴──────────┐             │
│                                      │        ▼                     ▼             │
│                                      │   ┌─────────┐          ┌─────────┐         │
│                                      │   │ L2      │          │ L1      │         │
│                                      │   │Verifier │          │ Keeper  │         │
│                                      │   └────┬────┘          └─────────┘         │
│                                      │        │                                   │
│                                      │        │ verified                          │
│                                      │        ▼                                   │
│                                      │   ┌────────────────────────────────────┐  │
│                                      │   │ SPIRIT (L3)                        │  │
│                                      │   │                                    │  │
│                                      │   │ [INBOX] "Research complete"        │  │
│                                      │   │    │                               │  │
│                                      │   │    ▼                               │  │
│                                      │   │ [DELIVER] time_sensitive? No       │  │
│                                      │   │           consequence? No          │  │
│                                      │   │           → NUDGE                  │  │
│  ┌──────────────┐  delivery payload  │   └────────────────────────────────────┘  │
│  │ Spirit UI    │ ◀─────────────────────                                         │
│  │              │                    │                                            │
│  │ 💭 "I found  │                    │                                            │
│  │  Tokyo info" │                    │                                            │
│  └──────┬───────┘                    │                                            │
│         │ user taps                  │                                            │
│         ▼                            │                                            │
│  ┌──────────────┐  {action: expand}  │   ┌────────────────────────────────────┐  │
│  │ Show details │ ─────────────────────▶ │ SPIRIT sends full content          │  │
│  └──────────────┘ ◀─────────────────────│                                    │  │
│                      full content    │   └────────────────────────────────────┘  │
│                                      │                                            │
└───────────────────────────────────────────────────────────────────────────────────┘
```

### Why This Split?

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Latency** | Voice on client | Real-time feel, no network delay |
| **Privacy** | Transcription on client | Audio never leaves device |
| **Compute** | LLM in cloud | Too heavy for mobile |
| **Tools** | Cloud containers | Browser, git need server env |
| **State** | World.log in cloud | Single source of truth for agents |
| **UI** | Client renders | Native animations, haptics |

## Implementation Status

### Spirit Pipeline
| Item | Status |
|------|--------|
| Note stage (observation) | ⬜ Not started |
| Background stage (silent work) | ⬜ Not started |
| Inbox stage (ready items) | ⬜ Not started |
| Delivery decision logic | ⬜ Not started |
| Time-sensitive detection | ⬜ Not started |
| Consequence evaluation | ⬜ Not started |

### Levels
| Item | Status |
|------|--------|
| L1: System Keeper (basic) | ✅ Done |
| L1: Cron integration | ⬜ Not started |
| L2: Verifier (basic) | ✅ Done |
| L2: Resume-based sessions | ⬜ Not started |
| L3: Spirit continuous session | ⬜ Not started |

### World Log
| Item | Status |
|------|--------|
| Event/Agent commands | ✅ Done |
| Check/Query commands | ✅ Done |
| Respond command | ✅ Done |

### Swift UI (Client)
| Item | Status |
|------|--------|
| Spirit floating window | ⬜ Not started |
| Visual states (idle/working/ready) | ⬜ Not started |
| Nudge delivery | ⬜ Not started |
| Interrupt delivery | ⬜ Not started |
| Silent (on-demand) access | ⬜ Not started |
| Voice capture + Whisper | ⬜ Not started |
| Speaker ID | ⬜ Not started |
| WebSocket client | ⬜ Not started |

### Cloud Infrastructure
| Item | Status |
|------|--------|
| Apple Container setup | ⬜ Not started |
| WebSocket server | ⬜ Not started |
| Spirit continuous session | ⬜ Not started |
| Task agent spawning | ⬜ Not started |
| World.log file watcher | ⬜ Not started |
