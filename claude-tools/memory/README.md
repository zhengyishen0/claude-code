# Memory

Cross-session knowledge sharing for Claude Code - search and consult previous sessions like a hive mind.

## Commands

### search

Search all sessions for matching content with boolean logic.

**Syntax:**
```bash
claude-tools memory search "OR terms" --and "AND terms" [--not "NOT terms"] [--recall "question"] [--limit N]
```

**Arguments:**
- First arg (required): OR terms - broaden search with synonyms/alternatives
- `--and` (required): AND terms - narrow by requiring at least one of these
- `--not` (optional): NOT terms - exclude sessions containing these

**Flags:**
- `--sessions N` - Number of sessions to return (default: 5)
- `--messages N` - Messages per session to show (default: 5)
- `--context N` - Characters of context per snippet (default: 300)
- `--recall "question"` - Ask matching sessions a question (parallel)

**Phrase support:** Use underscore to join words: `reset_windows` matches "reset windows"

**Examples:**
```bash
# Basic search: find ASUS-related sessions that mention specs
claude-tools memory search "asus laptop machine" --and "spec"

# With NOT to exclude test sessions
claude-tools memory search "chrome playwright" --and "click" --not "test"

# Search + recall in one step
claude-tools memory search "ollama devstral" --and "slow error" --recall "What problems with local LLMs?"

# Limit to 3 sessions
claude-tools memory search "auth" --and "jwt" --recall "How was JWT implemented?" --sessions 3
```

**Output format (search only):**
```
~/Codes/claude-code | 5a4020c4-ab2c-42b6-931e-0105c2060de8
Matches: 12 | Latest: 2025-12-04T08:59:42.725Z
[user] why did you propose the click and input command...
[asst] I see the button is showing up. Let me try...
... and 2 more

Found 72 matches across 26 sessions
```

**Output format (with --recall):**
```
~/Codes/claude-code | 5a4020c4-ab2c-42b6-931e-0105c2060de8
The ASUS laptop has 32GB RAM, Intel i7-12700H, RTX 3060...

~/Codes/other-project | abc123-def456-...
I found that the user mentioned an ASUS ROG laptop...
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

**Behavior:**
- By default, creates a fresh fork for each recall (predictable, consistent answers)
- Use `--resume` to reuse an existing fork for follow-up questions
- Fresh forks prevent context pollution and ensure independent answers

## Key Principles

1. **Incremental Indexing** - Full index on first run (~12s), incremental updates after (~0.5s)
2. **Clean Output** - Filters noise (tool results, IDE events, system messages)
3. **Grouped Results** - Messages grouped by session, sorted by recency
4. **Fresh Fork by Default** - Each recall creates a fresh fork for consistent, independent answers; use `--resume` for follow-up questions
5. **Parallel Recall** - Multiple sessions can be consulted in parallel
6. **Cross-Project Recall** - Sessions from any project can be recalled; resolves original project directory automatically
7. **Search + Recall** - Use `--recall` to search and ask in one step
8. **Explicit Flag Syntax** - `--and` and `--not` flags make query intent clear

## Two-Quality Framework for Effective Memory Retrieval

Successful memory recall requires both **query quality** (finding the right sessions) and **question quality** (getting relevant answers).

### 1. Query Quality (Search)

**Goal:** Find sessions that actually contain the information you need.

**Strategy:**
- **OR terms** (first argument): Broad synonyms and alternatives to maximize coverage
  - Example: `"asus laptop machine device"` - cast a wide net
- **AND terms** (`--and` flag): Specific terms that must appear to narrow results
  - Example: `--and "spec hardware gpu"` - at least one must match
- **NOT terms** (`--not` flag): Exclude irrelevant sessions
  - Example: `--not "test mock"` - filter out test-related sessions

**Good query example:**
```bash
# Looking for laptop specs
claude-tools memory search "asus laptop machine" --and "spec hardware ram cpu gpu"
```

**Bad query example:**
```bash
# Too narrow - might miss sessions that use different words
claude-tools memory search "asus" --and "specification"
```

### 2. Question Quality (Recall)

**Goal:** Ask questions that lead to relevant, specific answers.

**Key principles:**
- **Be explicit about domain** - Don't assume context carries over
- **Use specific terminology** - "hardware specs" not just "specs"
- **State what you're looking for** - List specific items you want

**Good question example:**
```bash
# Explicit, domain-specific, lists what we want
claude-tools memory recall "abc-123:What hardware specifications did the user mention about their ASUS laptop - specifically model name, GPU type, RAM amount, CPU, and ability to run LLMs locally?"
```

**Bad question example:**
```bash
# Vague - "specs" could mean anything (tool specs, API specs, etc.)
claude-tools memory recall "abc-123:What are the complete specs?"
```

**Why question quality matters:**
- The forked session sees your question without the current conversation context
- Vague terms like "specs" can be misinterpreted based on what the session discusses
- Example: A session about browser automation tools might interpret "specs" as "tool specifications" rather than "hardware specifications"

### 3. When to Use Each Approach

**Search only** (no recall):
- Exploratory: Want to see what sessions exist
- Quick reference: Just need to confirm something was discussed
- Multiple relevant sessions: Want to manually pick which one to consult

**Search + selective recall** (two-step):
- Need to review search results first
- Want to ask different questions to different sessions
- Iterative refinement: Adjust questions based on initial results

**Search + parallel recall** (--recall flag):
- Know exactly what you want to ask
- Same question applicable to all matching sessions
- Want fastest results (one command does everything)
- Most common use case

**Example decision tree:**
```bash
# "I know ASUS was mentioned somewhere, what sessions was that?"
claude-tools memory search "asus laptop" --and "spec"

# "I need the actual hardware specs that were mentioned"
claude-tools memory search "asus laptop" --and "spec hardware" \
  --recall "What hardware specs: model, GPU, RAM, CPU?"

# "I found the right session, now I have follow-up questions"
claude-tools memory recall "abc-123:What was the RAM?"
claude-tools memory recall --resume "abc-123:And the GPU?"  # reuse fork
```

## Technical Details

**Index:**
- Location: `~/.claude/memory-index.tsv`
- Format: `session_id\ttimestamp\ttype\ttext_preview\tproject_path`
- Extracts user/assistant messages, filters noise
- Incremental: only processes files newer than index

**Fork state:**
- Location: `~/.claude/memory-state/<session-id>.fork`
- Stores fork session ID for follow-up questions

**Search pipeline:**
```bash
# Query: memory search "chrome playwright" --and "click" --not "test"
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

**Search + recall in one step:**
```bash
claude-tools memory search "asus laptop" --and "spec" --recall "What are the specs?"
```

**Two-step workflow:**
```bash
# 1. Search with OR (broaden) and AND (narrow)
claude-tools memory search "asus laptop machine" --and "spec"
# Returns: ~/Codes/project | abc-123, ...

# 2. Found a promising session? Ask it directly (creates fresh fork)
claude-tools memory recall "abc-123:What ASUS laptop specs did the user mention?"

# 3. Follow-up questions? Use --resume to reuse the same fork
claude-tools memory recall --resume "abc-123:What was the RAM size?"
```

**Parallel recall for multiple sessions:**
```bash
claude-tools memory recall "abc:question1" "def:question2" "ghi:question3"
```
