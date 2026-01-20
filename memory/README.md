# Memory

Cross-session knowledge sharing for Claude Code - search and consult previous sessions like a hive mind.

## Quick Start

```bash
# Step 1: Search to explore
memory search "browser automation"

# Step 2: Refine keywords if results aren't relevant
memory search "browser click button"

# Step 3: When results look good, add --recall to get answers
memory search "browser click button" --recall "how to click a button by text?"
```

**Important:** Always refine your search keywords until you see relevant sessions BEFORE using `--recall`. The same keywords that find sessions also select which sessions get consulted.

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

#### Using --recall

**Workflow (must follow in order):**

1. **Search first** - See what sessions exist for your topic
2. **Refine keywords** - Adjust until results show relevant sessions
3. **Add --recall** - Same keywords, now consult those sessions

```bash
# Step 1: Search to see what's out there
memory search "worktree"
# → Too broad, shows unrelated sessions

# Step 2: Refine keywords
memory search "worktree create branch"
# → Better! Shows relevant sessions about creating worktrees

# Step 3: Now add --recall to get answers
memory search "worktree create branch" --recall "what is the command to create a worktree?"
```

**Why this order matters:** The keywords select which sessions get recalled. Bad keywords = consulting wrong sessions = useless answers.

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

1. **Search → Refine → Recall** - Always search first, refine keywords until results are relevant, then use --recall
2. **Simple by Default** - Just list keywords, no special syntax needed
3. **Smart Ranking** - Sessions matching more keywords rank higher (soft AND)
4. **Backward Compatible** - Use pipes for strict AND/OR when needed
5. **Incremental Indexing** - Full index on first run (~12s), incremental updates after (~0.5s)
6. **Clean Output** - Filters noise (tool results, IDE events, system messages)
7. **Cross-Project Recall** - Sessions from any project can be searched and consulted

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
