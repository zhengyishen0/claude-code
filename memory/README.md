# Memory

Cross-session knowledge sharing for Claude Code - search and consult previous sessions like a hive mind.

## Quick Start

```bash
# Step 1: Search to explore
memory search "browser automation"

# Step 2: If snippets answer your question, you're done!

# Step 3: If you need deeper answers, use --recall
memory search "browser click button" --recall "how to click a button by text?"
```

**Key point:** Search snippets often contain enough information. Only use `--recall` when you need deeper context or synthesized answers from multiple sessions.

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

#### Flags

- `--sessions N` - Number of sessions to return (default: 10)
- `--messages N` - Messages per session to show (default: 5)
- `--context N` - Characters of context per snippet (default: 300)
- `--recall "question"` - After finding sessions, ask them your question directly (parallel)

**Phrase support:** Use underscore to join words: `reset_windows` matches "reset windows"

#### Using --recall (optional)

**When to use --recall:**
- Search snippets don't contain enough detail
- You need a synthesized answer from multiple sessions
- You have a specific question that needs context

**When NOT to use --recall:**
- Search snippets already answer your question
- You just need to know which sessions discussed a topic

```bash
# Search first
memory search "worktree create"
# → If snippets show the command, you're done!

# Only use --recall if you need more detail
memory search "worktree create" --recall "what are the cleanup steps after merge?"
```

**Important:** The same keywords select which sessions get recalled. Refine your search until results are relevant before adding --recall.

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

## Key Principles

1. **Search First** - Always start with search, snippets may be enough
2. **Recall is Optional** - Only use --recall when snippets aren't sufficient
3. **Refine Before Recall** - Good keywords = good recall results
4. **Simple by Default** - Just list keywords, no special syntax needed
5. **Smart Ranking** - Sessions matching more keywords rank higher (soft AND)
6. **Incremental Indexing** - Full index on first run (~12s), incremental updates after (~0.5s)
7. **Cross-Project** - Sessions from any project can be searched and consulted

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
- **Python 3** - For result formatting (no external dependencies)
- **Claude Code CLI** - For recall/fork functionality
