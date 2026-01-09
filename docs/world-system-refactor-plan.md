# World System Refactor Plan

Refactoring environment + manager → world + supervisors

## Overview

| Current | New | Purpose |
|---------|-----|---------|
| `claude-tools/environment/` | `claude-tools/world/` | Log tool |
| `environment.log` | `world.log` | Single source of truth |
| `claude-manager/` | `claude-tools/world/supervisors/` | Level 1 + Level 2 |

## Design Philosophy

- **Simplicity**: Plain text, grep-able, AI-native
- **Minimum tools, maximum access**: One log for coordination + tracking
- **Log as truth**: If not in log, didn't happen
- **"件件有着落"**: Every intention reaches verified/failed

---

## Phase 1: Log Format Migration

### Current Format
```
[timestamp] [source] [task-id:status] description
```

### New Format
```
# Events (facts, no tracking)
[timestamp][event:source][identifier] output

# Agents (projects, tracked lifecycle)
[timestamp][agent:status][session-id] output | need: criteria
```

### Tasks

- [ ] Define exact format spec in README
- [ ] Update `run.sh` to write new format
- [ ] Add `event` command with source/identifier params
- [ ] Add `agent` command with status/session-id params
- [ ] Keep backward compatibility during migration (read old, write new)
- [ ] Add format validation (optional, warn on malformed)

### Event Sources
| Source | Identifier Example |
|--------|-------------------|
| `chrome` | `airbnb.com/s/Paris` |
| `bash` | `git-status` |
| `file` | `src/config.json` |
| `api` | `api.stripe.com/charges` |
| `system` | `session-abc123` |
| `user` | `session-abc123` |

### Agent Statuses
| Status | Meaning | Triggered By |
|--------|---------|--------------|
| `start` | Project created | User/System |
| `active` | Agent running | Agent |
| `finish` | Agent thinks done | Agent |
| `verified` | Success confirmed | Level 2 |
| `retry` | Try again | Level 2 |
| `failed` | Cannot proceed | Agent/Level 2 |

---

## Phase 2: Tool Restructure

### Current Structure
```
claude-tools/
└── environment/
    ├── run.sh
    ├── README.md
    └── environment.log

claude-manager/
├── run.sh
├── README.md
└── system-prompt.md
```

### New Structure
```
claude-tools/
└── world/
    ├── run.sh              # Main entry point
    ├── README.md           # Full spec
    ├── world.log           # The log
    ├── commands/
    │   ├── event.sh        # Log event
    │   ├── agent.sh        # Log agent status
    │   ├── check.sh        # Read with marker
    │   └── query.sh        # Common queries
    └── supervisors/
        ├── level1.sh       # State enforcer (pure code)
        ├── level2.md       # Intention verifier (AI prompt)
        └── run.sh          # Supervisor daemon
```

### Tasks

- [ ] Create `claude-tools/world/` directory
- [ ] Move and rename `environment.log` → `world.log`
- [ ] Split commands into separate files
- [ ] Update `run.sh` router
- [ ] Update CLAUDE.md tool documentation
- [ ] Deprecate `claude-tools/environment/` (keep for transition)
- [ ] Deprecate `claude-manager/` (merge into world/supervisors)

---

## Phase 3: Level 1 Supervisor (Pure Code)

### Purpose
Enforce: world.log state = actual system state

### Logic
```bash
# Every N seconds
log_agents=$(rg '\[agent:active\]' world.log | extract_session_ids)
running=$(pgrep -f "claude" | get_session_ids)

# Start missing
for id in $log_agents; do
    if not in $running; then
        restart_agent $id
        log "[event:system][$id] restarted | reason: not running"
    fi
done

# Kill orphans
for pid in $running; do
    if not in $log_agents; then
        kill $pid
        log "[event:system][$pid] killed | reason: orphan"
    fi
done
```

### Tasks

- [ ] Create `supervisors/level1.sh`
- [ ] Implement agent state parsing from log
- [ ] Implement process detection
- [ ] Implement start/kill logic
- [ ] Add to supervisor daemon loop
- [ ] Test with mock scenarios

---

## Phase 4: Level 2 Supervisor (AI Agent)

### Purpose
Ensure every agent reaches `verified` or `failed`

### Logic
```
For each agent where status = "finish":
    Read output
    Read success criteria (from start entry)

    If output satisfies criteria:
        Log [agent:verified][id]
    Else:
        If retry_count < max:
            Log [agent:retry][id] prompt="guidance"
        Else:
            Log [agent:failed][id] reason="max retries"
            Escalate to user

For each agent where status = "active":
    If no activity for threshold:
        Log [agent:retry][id] prompt="continue"
```

### Tasks

- [ ] Create `supervisors/level2.md` (system prompt)
- [ ] Define verification logic in prompt
- [ ] Define retry guidance generation
- [ ] Define escalation triggers
- [ ] Integrate with supervisor daemon
- [ ] Test verification flow

---

## Phase 5: Human in the Loop

### Escalation Flow
```
[agent:failed][abc123] Captcha required | need: solve captcha
[event:system][abc123] Solve captcha at example.com/captcha
[event:user][abc123] Captcha solved: boats
[agent:retry][abc123] User provided input, continuing
[agent:active][abc123] Resuming
```

### Tasks

- [ ] Define `[event:user]` entry format
- [ ] Implement user input mechanism (CLI first)
- [ ] Level 2 watches for `[event:user]`, triggers retry
- [ ] Test escalation → input → retry flow
- [ ] (Future) Add notification layer (macOS, voice)

---

## Phase 6: Integration & Migration

### Tasks

- [ ] Update all tools that write to environment.log
- [ ] Update chrome tool to log `[event:chrome]`
- [ ] Update bash wrapper to log `[event:bash]`
- [ ] Add file watcher for `[event:file]`
- [ ] Test full flow: user → agent → events → finish → verify
- [ ] Document migration path for existing logs
- [ ] Remove deprecated environment/manager code

---

## Testing Checklist

- [ ] Event logging (all sources)
- [ ] Agent lifecycle (start → active → finish → verified)
- [ ] Agent retry flow (finish → retry → active → finish → verified)
- [ ] Agent failure flow (failed → user input → retry → verified)
- [ ] Level 1: orphan detection and cleanup
- [ ] Level 1: missing agent restart
- [ ] Level 2: verification against success criteria
- [ ] Level 2: retry with guidance
- [ ] Level 2: escalation to user
- [ ] Read marker system (unchanged)
- [ ] Query examples with rg

---

## Success Criteria

1. **All events logged consistently** in new format
2. **All agents tracked** through complete lifecycle
3. **Level 1 enforces** log = system state
4. **Level 2 verifies** every finish → verified or failed
5. **Human escalation** works end-to-end
6. **"件件有着落"**: No agent left in limbo

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking existing workflows | Keep backward compatibility during transition |
| Log format parsing errors | Add validation, warn on malformed |
| Level 1 kills wrong processes | Conservative matching, dry-run mode |
| Level 2 false verifications | Start with human review, tune criteria |

---

## Timeline

| Phase | Dependency | Effort |
|-------|------------|--------|
| Phase 1: Log Format | None | Foundation |
| Phase 2: Tool Restructure | Phase 1 | Reorganization |
| Phase 3: Level 1 | Phase 2 | Pure code |
| Phase 4: Level 2 | Phase 2 | AI prompt |
| Phase 5: Human Loop | Phase 4 | Integration |
| Phase 6: Migration | All | Cleanup |

---

## Notes

- Start with Phase 1-2, get format right
- Level 1 is simpler, build first
- Level 2 evolves from current manager
- Human loop can be CLI-only initially
- Notification layer is future work
