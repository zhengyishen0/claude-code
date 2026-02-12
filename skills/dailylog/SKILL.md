---
name: dailylog
description: Unified daily log for sessions, lessons, and jj changes
---

# dailylog

Manages daily logs in `vault/logs/YYYY-MM-DD.md`.

## Commands

```bash
dailylog session "Title" [-c "content"]     # Add session entry
dailylog lesson L001 "WHEN->DO->BECAUSE"    # Add lesson entry
dailylog jj abc123 "message" [-t tag]       # Add jj commit
dailylog jj-graph                           # Dump jj graph
dailylog show [date]                        # Show log (today or date)
dailylog list [-n 7]                        # List recent logs
dailylog search "query" [-l]                # Search logs (-l for lessons only)
```

## Daily Log Structure

```markdown
---
date: 2026-02-12
---

# 2026-02-12

## Sessions
### 14:32 - Memory system design
- Discussed daily log integration
- Decided to unify lessons + jj

## Lessons
- [L001] WHEN designing memory -> DO separate types -> BECAUSE clear routing

## JJ Changes
- `abc1234` [decision] memory: daily log spec

## JJ Graph
```

## Integration

- **Sessions**: Pre-compaction hook or manual `dailylog session`
- **Lessons**: `lesson add` also writes to daily log
- **JJ**: Wrapper function syncs commits automatically
