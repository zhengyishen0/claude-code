# Memory

Cross-session knowledge sharing for Claude Code - search and consult previous sessions like a hive mind.

## Commands

### search

Search all sessions for matching content with boolean logic.

**Syntax:**
```bash
claude-tools memory search [--limit N] [--summary] "<query>"
```

**Flags:**
- `--limit N` - Messages per session (default: 5)
- `--summary`, `-s` - Summarize results with haiku (~90s)

**Query syntax:**
- `term1 term2` - OR (space-separated, finds either term)
- `word_word` - PHRASE (underscore joins words, matches exact phrase)
- `+term` - AND (must include this term)
- `-term` - NOT (must exclude this term)

**Examples:**
```bash
# Simple keyword search
claude-tools memory search "authentication"

# OR search (finds 'chrome' OR 'playwright')
claude-tools memory search "chrome playwright"

# PHRASE search (finds 'reset windows' as exact phrase)
claude-tools memory search "reset_windows"

# AND search (finds 'chrome' AND 'click')
claude-tools memory search "chrome +click"

# NOT search (finds 'error' but NOT 'test')
claude-tools memory search "error -test"

# Combined: PHRASE + AND
claude-tools memory search "Tesla_Model_3 +price"

# Combined: OR + AND + NOT
claude-tools memory search "chrome playwright +click -test"

# With summarization (slower but condensed)
claude-tools memory search --summary "error_handling"
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
6. **Cross-Project Recall** - Sessions from any project can be recalled; resolves original project directory automatically
7. **Fast by Default** - Raw results returned instantly; use `--summary` for AI-condensed output (~90s)
8. **Simple Query Syntax** - Space = OR, underscore = PHRASE, + = AND, - = NOT

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
# Query: "chrome playwright +click -test"
# Parsed as: OR(chrome, playwright) AND(click) NOT(test)
# Becomes:
rg -i '(chrome|playwright)' index.tsv | rg -i 'click' | grep -iv 'test'

# Phrase: "reset_windows" -> "reset.windows" (regex matches any separator)
```

## Cross-Project Session Resolution

When recalling a session from a different project, the tool:
1. Searches all projects in `~/.claude/projects/` for the session ID
2. Extracts the project path from the directory name (e.g., `-Users-foo-bar` -> `/Users/foo/bar`)
3. Handles directory names with dashes by testing each segment against the filesystem
4. Runs `claude --resume` from the original project directory so file references work correctly

## Requirements

- **ripgrep** (rg) - Fast text search
- **jq** - JSON processing
- **Claude Code CLI** - For recall/fork functionality

## Workflow

**Typical search→recall flow:**
```bash
# 1. Search broadly with OR (fast, instant results)
claude-tools memory search "asus laptop specs"
# Returns: Session abc-123, Session def-456, ...

# 2. Found a promising session? Ask it directly
claude-tools memory recall "abc-123:What ASUS laptop specs did the user mention?"

# 3. Follow-up questions reuse the same fork
claude-tools memory recall "abc-123:What was the RAM size?"

# 4. Start fresh when switching topics
claude-tools memory recall --new "abc-123:Different question"
```

**Narrowing search with AND/NOT:**
```bash
# Too many results? Add +AND to narrow
claude-tools memory search "asus +laptop"

# Exclude noise with -NOT
claude-tools memory search "asus +laptop -test"
```

**Parallel recall for multiple sessions:**
```bash
claude-tools memory recall "abc:question1" "def:question2" "ghi:question3"
```
