# Memory

Cross-session knowledge sharing for Claude Code - search and consult previous sessions like a hive mind.

## Commands

### search

Search all sessions for matching content.

**Two modes (auto-detected by presence of pipes):**

#### Simple Mode (recommended)

Just list keywords separated by spaces. All keywords are OR'd together, and results are ranked by how many keywords match.

```bash
claude-tools memory search "keyword1 keyword2 keyword3"
```

**How it works:**
- Matches ANY keyword (broad search)
- Ranks by: keyword hits → match count → recency
- Sessions matching more keywords appear first
- Best for exploratory searches

**Examples:**
```bash
# Find sessions about chrome automation
claude-tools memory search "chrome automation workflow"
# → Sessions matching all 3 keywords rank highest
# → Sessions matching 2 keywords rank next
# → Sessions matching 1 keyword still shown (lower)

# Find authentication discussions
claude-tools memory search "JWT OAuth authentication tokens"

# Find debugging sessions
claude-tools memory search "error debug fix bug"
```

#### Strict Mode (advanced)

Use pipes (`|`) for OR within groups and spaces for AND between groups. Requires matching at least one term from EACH group.

```bash
claude-tools memory search "group1term1|group1term2 group2term1|group2term2"
```

**How it works:**
- Pipes = OR within group
- Spaces = AND between groups
- Must match at least one term from EACH group
- Best when you need specific term combinations

**Examples:**
```bash
# (chrome OR browser) AND (automation OR workflow)
claude-tools memory search "chrome|browser automation|workflow"

# (JWT OR OAuth) AND implementation
claude-tools memory search "JWT|OAuth implementation"

# (error OR bug) AND (fix OR solve OR patch)
claude-tools memory search "error|bug fix|solve|patch"
```

#### Common Flags

- `--sessions N` - Number of sessions to return (default: 10)
- `--messages N` - Messages per session to show (default: 5)
- `--context N` - Characters of context per snippet (default: 300)
- `--recall "question"` - Ask matching sessions a question (parallel)

**Phrase support:** Use underscore to join words: `reset_windows` matches "reset windows"

**Output format (simple mode):**
```
~/Codes/claude-code | 5a4020c4-ab2c-42b6-931e-0105c2060de8 | 3/3 keywords, 47 matches | 2025-12-04T08:59:42.725Z
[user] why did you propose the click and input command...
[asst] I see the button is showing up. Let me try...
... and 42 more matches

Found matches in 10 sessions (searched 3 keywords)
```

**Output format (strict mode):**
```
~/Codes/claude-code | 5a4020c4-ab2c-42b6-931e-0105c2060de8 | 47 matches | 2025-12-04T08:59:42.725Z
[user] why did you propose the click and input command...
[asst] I see the button is showing up. Let me try...
... and 42 more matches

Found matches in 10 sessions (strict mode)
```

### recall

Consult a session by forking it and asking a question.

**Syntax:**
```bash
claude-tools memory recall [--resume] "<session-id>:<question>" [...]
```

**Flags:**
- `--resume`, `-r` - Reuse existing fork for follow-up questions

**Examples:**
```bash
# Single query (fresh fork by default)
claude-tools memory recall "abc-123:How did you handle errors?"

# Follow-up question (reuse existing fork)
claude-tools memory recall --resume "abc-123:What about edge cases?"

# Multiple queries (parallel, all fresh forks)
claude-tools memory recall "session1:question1" "session2:question2"
```

## Key Principles

1. **Simple by Default** - Just list keywords, no special syntax needed
2. **Smart Ranking** - Sessions matching more keywords rank higher (soft AND)
3. **Backward Compatible** - Use pipes for strict AND/OR when needed
4. **Incremental Indexing** - Full index on first run (~12s), incremental updates after (~0.5s)
5. **Clean Output** - Filters noise (tool results, IDE events, system messages)
6. **Fresh Fork by Default** - Each recall creates a fresh fork; use `--resume` for follow-ups
7. **Cross-Project Recall** - Sessions from any project can be recalled

## When to Use Each Mode

| Use Case | Mode | Example |
|----------|------|---------|
| Exploratory search | Simple | `"chrome automation debug"` |
| Find related topics | Simple | `"JWT OAuth tokens security"` |
| Require specific terms together | Strict | `"chrome\|browser automation"` |
| Complex boolean logic | Strict | `"error\|bug fix\|solve\|patch"` |

**Rule of thumb:** Start with simple mode. Use strict mode only when simple mode returns too many irrelevant results.

## Technical Details

**Index:**
- Location: `~/.claude/memory-index.tsv`
- Format: `session_id\ttimestamp\ttype\ttext_preview\tproject_path`
- Incremental: only processes files newer than index

**Search pipeline:**
```bash
# Simple mode: "chrome automation workflow"
# → OR all keywords, rank by keyword hits
rg -i '(chrome|automation|workflow)' index.tsv | python3 format-results.py

# Strict mode: "chrome|browser automation|workflow"
# → Chain rg for each AND group
cat index.tsv | rg -i '(chrome|browser)' | rg -i '(automation|workflow)'
```

## Requirements

- **ripgrep** (rg) - Fast text search
- **jq** - JSON processing
- **pandas** - Python data processing
- **Claude Code CLI** - For recall/fork functionality
