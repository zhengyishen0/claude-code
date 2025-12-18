# Memory

Cross-session knowledge sharing for Claude Code - search and consult previous sessions like a hive mind.

## Commands

### search

Search all sessions for matching content with boolean logic.

**Syntax:**
```bash
claude-tools memory search "<query>"
```

**Query syntax:**
- `term1|term2` - OR (first term, rg pattern)
- `term` - AND (space-separated)
- `-term` - NOT (dash prefix)

**Examples:**
```bash
# Simple keyword search
claude-tools memory search "authentication"

# OR search
claude-tools memory search "chrome|playwright"

# AND search (space-separated)
claude-tools memory search "chrome click"

# NOT search (dash prefix)
claude-tools memory search "error -test"

# Combined: OR, AND, NOT
claude-tools memory search "chrome|playwright click -test"
```

**Output format:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Session: 5a4020c4-ab2c-42b6-931e-0105c2060de8
Matches: 12 | Latest: 2025-12-04T08:59:42.725Z
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[user] why did you propose the click and input command...
[asst] I see the button is showing up. Let me try...
[asst] Done! Here's a summary of the changes...
... and 2 more

Found 72 matches across 26 sessions
```

### recall

Consult a session by forking it and asking a question.

**Syntax:**
```bash
claude-tools memory recall [--new] "<session-id>:<question>" [...]
```

**Flags:**
- `--new`, `-n` - Force new fork (ignore existing fork)

**Examples:**
```bash
# Single query
claude-tools memory recall "abc-123:How did you handle errors?"

# Force new fork
claude-tools memory recall --new "abc-123:Start fresh question"

# Multiple queries (parallel)
claude-tools memory recall "session1:question1" "session2:question2"
```

**Behavior:**
- First query creates a fork with `--fork-session`
- Follow-up questions reuse the same fork
- Use `--new` to force a fresh fork

## Key Principles

1. **Incremental Indexing** - Full index on first run (~12s), incremental updates after (~0.5s)
2. **Clean Output** - Filters noise (tool results, IDE events, system messages)
3. **Grouped Results** - Messages grouped by session, sorted by recency
4. **Fork Tracking** - Follow-up questions reuse same fork for context
5. **Parallel Recall** - Multiple sessions can be consulted in parallel

## Technical Details

**Index:**
- Location: `~/.claude/memory-index.tsv`
- Format: `session_id\ttimestamp\ttype\ttext_preview`
- Extracts user/assistant messages, filters noise
- Incremental: only processes files newer than index

**Fork state:**
- Location: `~/.claude/memory-state/<session-id>.fork`
- Stores fork session ID for follow-up questions

**Search pipeline:**
```bash
# Query: "chrome|playwright click -test"
# Becomes:
rg -i '(chrome|playwright)' index.tsv | rg -i 'click' | grep -iv 'test'
```

## Requirements

- **ripgrep** (rg) - Fast text search
- **jq** - JSON processing
- **Claude Code CLI** - For recall/fork functionality

## Workflow

```bash
# 1. Search for relevant sessions
claude-tools memory search "authentication"

# 2. Pick a session and ask questions
claude-tools memory recall "abc-123:How did you implement JWT?"

# 3. Follow-up (reuses same fork)
claude-tools memory recall "abc-123:What about refresh tokens?"

# 4. Start fresh when needed
claude-tools memory recall --new "abc-123:Different topic"
```
