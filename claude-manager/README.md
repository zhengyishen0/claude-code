# claude-manager

Event processing service that continuously monitors and processes environment events.

## Commands

### start
Start the manager daemon in background.

```bash
claude-manager/run.sh start
```

The manager will:
- Loop continuously (every 5-30 minutes based on activity)
- Check for new events using `environment check`
- Process events with Claude (opus model, -p mode)
- Take actions by creating new events
- Log lifecycle to environment.log

### stop
Stop the running manager daemon.

```bash
claude-manager/run.sh stop
```

Kills the background process and logs stop event.

### status
Check if manager is running.

```bash
claude-manager/run.sh status
```

Shows PID and session ID if running.

## How It Works

**Manager lifecycle is tracked in environment.log:**

```
[2024-01-15T09:00:00Z] [system] [12345-a7f3c1:started] manager started
...
[2024-01-15T18:00:00Z] [system] [12345-a7f3c1:stopped] manager stopped
```

Format: `[PID-SessionID:status]`
- PID = Process ID
- SessionID = Unique 8-char identifier for this run
- Status = started or stopped

**Processing loop:**
1. Call `environment check` to get new events
2. If events exist:
   - Process with Claude using opus model
   - Claude creates new events via environment tool
   - Immediately check again (no sleep)
3. If no events:
   - Sleep 5 minutes (first idle)
   - Sleep 30 minutes (still idle)

## Example Usage

```bash
# Start manager
claude-manager/run.sh start
# Output: Manager started
#         PID: 12345
#         Session: a7f3c1

# Add a task
claude-tools/environment/run.sh event [user] [task-001:active] "build company website"

# Manager wakes (within 5 min), processes task, breaks it down

# Check status
claude-manager/run.sh status
# Output: Manager running
#         PID: 12345
#         Session: a7f3c1

# Stop
claude-manager/run.sh stop
# Output: Manager stopped
```

## Progressive Sleep

- **Active (new events):** Check immediately, no sleep
- **First idle:** Sleep 5 minutes
- **Still idle:** Sleep 30 minutes

This balances responsiveness with cost efficiency.

## Cost Estimate

- Active day: ~40-60 Claude calls = $1.20-1.80/day
- Quiet day: ~10-15 Claude calls = $0.30-0.45/day
- Average: ~$20-30/month for 24/7 operation
