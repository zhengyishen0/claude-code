# World Supervisors

Two-level supervision system ensuring "件件有着落" (nothing falls through).

## Overview

| Level | Name | Type | Job |
|-------|------|------|-----|
| **Level 1** | State Enforcer | Pure code | Log state = System state |
| **Level 2** | Intention Verifier | AI-capable | Every agent → verified or failed |

## Commands

### Run Both Supervisors

```bash
# Run once
claude-tools world supervisor once

# Run as daemon (continuous)
claude-tools world supervisor daemon
```

### Level 1: State Enforcer

```bash
claude-tools world supervisor level1 check    # Check discrepancies
claude-tools world supervisor level1 enforce  # Fix discrepancies
claude-tools world supervisor level1 status   # Show agent states
```

**What it does:**
- Compares log state to running processes
- Starts agents that should be running but aren't
- Kills orphan processes not in log

### Level 2: Intention Verifier

```bash
claude-tools world supervisor level2 check    # Check what needs attention
claude-tools world supervisor level2 process  # Process pending items
claude-tools world supervisor level2 status   # Show verification status
```

**What it does:**
- Verifies `finish` outputs against `| need:` criteria
- Retries with guidance if not verified
- Handles user input for failed agents
- Escalates when max retries reached

## Human-in-the-Loop

When an agent fails and needs human input:

```bash
# Agent fails
[agent:failed][abc123] captcha required | need: solve captcha

# System escalates
[event:system][abc123] escalated to user

# Human responds
claude-tools world respond abc123 "captcha solved: boats"

# Level 2 triggers retry
claude-tools world supervisor level2 process
```

## Agent Lifecycle

```
start → active → finish → verified ✓
                    ↓
                  retry → active → finish → verified ✓
                    ↓
                  failed → (user input) → retry → active ...
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_RETRIES` | 3 | Max retry attempts before failing |
| `STALE_THRESHOLD` | 3600 | Seconds before active agent is stale |
| `POLL_INTERVAL` | 60 | Seconds between daemon cycles |
| `DRY_RUN` | false | Show actions without executing |

## Verification Logic

Level 2 uses keyword matching to verify outputs:

1. Extract key terms from `| need:` criteria
2. Check if terms appear in finish output
3. Require 50%+ term match for verification

For production, this can be enhanced with AI-based verification.
