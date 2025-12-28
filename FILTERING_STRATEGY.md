# Memory Search Filtering Strategy

## Overview: Message-Level vs Session-Level Filtering

Memory search uses **two distinct filtering approaches**:

1. **Session-Level Filtering** - Exclude entire sessions (all messages from that session)
2. **Message-Level Filtering** - Exclude individual messages within sessions

This distinction is critical for understanding what gets filtered and when.

---

## STAGE 1: INDEXING (Build Time)

**Goal:** Build clean, searchable index from session JSONL files
**Location:** `search.sh:89-161`

### Input
- All `.jsonl` files in `~/.claude/projects/*/`
- Each file = one session's conversation history

---

## SESSION-LEVEL FILTERING (Index Time)

**Entire sessions excluded - no messages from these sessions get indexed**

### 1.1 Fork Sessions
**Pattern:** First line contains `"type":"queue-operation"`
**Reason:** Temporary sessions created by memory recall - these are ephemeral forks, not original work
**Code:** Line 94

```bash
if ! head -1 "$file" | jq -e 'select(.type == "queue-operation")' >/dev/null 2>&1; then
  echo "$file"
fi
```

**Example:**
```
Session: abc-123.jsonl
  First line: {"type":"queue-operation",...}
  Result: ENTIRE SESSION EXCLUDED (all messages skipped)
```

### 1.2 Current Session
**Pattern:** `session_id == $CURRENT_SESSION_ID`
**Reason:** Exclude the session you're currently in - you don't want to see your own current conversation
**Code:** Line 116

```bash
select($session_id != "'$CURRENT_SESSION_ID'") |
```

**Example:**
```
Current session ID: xyz-789
Indexing session: xyz-789.jsonl
  Result: ENTIRE SESSION EXCLUDED
Indexing session: abc-123.jsonl
  Result: Session indexed normally
```

**Why session-level?** These are structural exclusions - we never want ANY messages from these sessions, so filtering the entire session is more efficient than checking every message.

---

## MESSAGE-LEVEL FILTERING (Index Time)

**Individual messages excluded - some messages from a session may be kept, others filtered**

### 2.1 Content Quality Filters

| Filter | Pattern | Reason | Code |
|--------|---------|--------|------|
| **Short messages** | `length < 10` chars | Too short to be meaningful | 109 |

**Example:**
```
Session abc-123.jsonl has 5 messages:
  Message 1: "Help me implement JWT" (21 chars) → KEEP
  Message 2: "ok" (2 chars) → EXCLUDE (too short)
  Message 3: "Here's the implementation..." (500 chars) → KEEP
  Message 4: "thanks" (6 chars) → EXCLUDE (too short)
  Message 5: "Can you also add refresh tokens?" (33 chars) → KEEP

Result: Session indexed with messages 1, 3, 5 (2 and 4 excluded)
```

### 2.2 System Noise Filters

**Tool/System patterns** - Code line 110

| Pattern | What it excludes | Example |
|---------|------------------|---------|
| `<function_calls>`, `<invoke>`, `</invoke>`, `<parameter>`, `</parameter>`, `</function_calls>` | Tool call XML syntax | `<function_calls><invoke name="Bash">...` |
| `<bash-` | Bash tool result markers | `<bash-123>` |
| `<ide_` | IDE events | `<ide_file_opened>`, `<ide_selection>` |
| `[Request interrupted` | Interrupted requests | `[Request interrupted by user]` |
| `New environment` | Session startup messages | `New environment detected` |
| `API Error` | API errors | `API Error: Rate limit exceeded` |
| `Limit reached` | Rate limit messages | `Limit reached for model` |
| `Caveat:` | System warnings | `Caveat: This feature is experimental` |

```bash
select($text | test("<ide_|\\[Request interrupted|New environment|API Error|...") | not) |
```

**Example:**
```
Session abc-123.jsonl has 4 messages:
  Message 1: "Help me debug this" → KEEP
  Message 2: "<ide_file_opened path='/foo/bar.js'>" → EXCLUDE (IDE event)
  Message 3: "API Error: Rate limit exceeded" → EXCLUDE (error message)
  Message 4: "I'll help you debug. First..." → KEEP

Result: Session indexed with messages 1, 4 (2 and 3 excluded)
```

### 2.3 Recall Output Filters

**Pattern:** `^\[[0-9]+/[0-9]+]\s+[a-f0-9]{7}\s+•`
**Reason:** These are outputs from previous memory recalls showing session summaries
**Code:** Line 112

```bash
select($text | test("^\\[[0-9]+/[0-9]+\\]\\s+[a-f0-9]{7}\\s+•") | not) |
```

**Example:**
```
Message text: "[1/5] abc1234 • Dec 28
This session discussed JWT implementation..."

Result: EXCLUDE (this is recall output, not original content)
```

**Why message-level?** These filters identify specific message characteristics - we want to keep the session but filter individual low-quality or noisy messages.

---

## Index Output Format

**After all filtering:**

```tsv
session_id \t timestamp \t type \t text \t project_path
```

**Example:**
```
abc-123	2024-12-28T10:30:00Z	user	How do I implement JWT authentication?	/Users/me/project
abc-123	2024-12-28T10:31:15Z	assistant	I'll help you implement JWT auth...	/Users/me/project
def-456	2024-12-27T14:20:00Z	user	Can you explain git rebase?	/Users/me/other-project
```

**Typical reduction:** ~40-60% of raw messages filtered out

---

## STAGE 2: QUERY SEARCH (Search Time)

**Goal:** Find messages matching user's query
**Location:** `search.sh:263-301`

### MESSAGE-LEVEL FILTERING ONLY

Search operates **only at message level** - it filters individual messages that don't match the query.

### Input
- User query with optional filters
- Clean index from Stage 1

### 2.1 Simple Mode (default)

```bash
memory search "authentication jwt" --require "implement" --exclude "test"
```

**Pipeline:**
```
rg -i "(authentication|jwt)" index.tsv  # OR: match either term (message-level)
  | rg -i "implement"                    # AND: must contain (message-level)
  | grep -iv "test"                      # NOT: must not contain (message-level)
```

**Example:**
```
Index has 10 messages from session abc-123:
  Message 1: "authentication setup" → MATCH (has 'authentication')
  Message 2: "implement jwt tokens" → MATCH (has 'jwt' + 'implement')
  Message 3: "testing the auth flow" → EXCLUDE (has 'test')
  Message 4: "database configuration" → NO MATCH (no search terms)
  Message 5: "implement authentication service" → MATCH (all criteria)
  ...

Result: 3 messages from session abc-123 match (messages 1, 2, 5)
```

### Output
- TSV lines matching query criteria (message-level matches)
- Lines sorted and deduplicated (`sort -u`)

---

## STAGE 3: POST-SEARCH FILTERING (Recall Cutoff)

**Goal:** Remove messages contaminated by previous memory recalls
**Location:** `search.sh:310-341`

### MESSAGE-LEVEL FILTERING (Temporal)

This is a **time-based message filter** - excludes messages before recall events.

### Input
- Search results from Stage 2
- Format: `session_id \t timestamp \t type \t text \t project_path`

### 3.1 Detection Phase

**Find recall events (message-level detection):**

| Pattern | Example |
|---------|---------|
| `I'll search` | "I'll search memory for previous work" |
| `memory search` | "Let me run memory search" |
| `Did you remember.*talked about` | "Did you remember we talked about this?" |
| `go back to a memory` | "Let me go back to a memory of that" |
| `memory recall` | "I'll use memory recall to check" |

**Extract cutoff points per session:**
```bash
RECALL_CUTOFFS=$(echo "$RESULTS" | awk -F'\t' '$4 ~ /(patterns...)/ {print $1 "\t" $2}')

# Example output:
abc-123	2024-12-28T10:35:00Z   # Recall happened at 10:35 in session abc-123
def-456	2024-12-27T15:00:00Z   # Recall happened at 15:00 in session def-456
```

### 3.2 Exclusion Phase (Message-Level)

**For each message in results:**
```python
if session has recall cutoff timestamp:
    if message.timestamp <= cutoff:
        EXCLUDE  # Message happened before recall, might be tainted
    else:
        KEEP     # Message happened after recall
else:
    KEEP         # Session never used recall
```

**Example:**
```
Session abc-123 has recall cutoff at 10:35:00

Message 1 (10:30:00): "How to implement JWT?" → EXCLUDE (before cutoff)
Message 2 (10:31:00): "Here's the implementation..." → EXCLUDE (before cutoff)
Message 3 (10:35:00): "I'll search memory for Chrome work" → EXCLUDE (AT cutoff)
Message 4 (10:40:00): "Now about that JWT refresh token..." → KEEP (after cutoff)

Result: Only message 4 kept (messages 1-3 excluded due to recall cutoff)
```

### ⚠️ Known Issue: Too Aggressive

**Problem:** This is a **session-aware message filter** that excludes ALL messages before recall, even valuable unrelated work.

**Better approach:** Should be a **context-aware message filter** that only excludes recall-related messages, not all prior work.

### Output
- Filtered TSV lines (recall-contaminated messages removed)

---

## STAGE 4: RANKING (Presentation)

**Goal:** Order sessions by relevance and format for display
**Location:** `format-results.py:42-96`

### SESSION-LEVEL AGGREGATION + MESSAGE-LEVEL LIMITING

This stage works at **both levels**:
1. Aggregates message-level data into session-level stats
2. Filters messages per session for display

### Input
- Filtered TSV lines from Stage 3

### 4.1 Session-Level Grouping

```python
# Aggregate messages by session
session_stats = df.groupby('session_id').agg({
    'timestamp': 'max',      # Latest message timestamp (session-level)
    'project_path': 'first', # Project path (session-level)
    'session_id': 'count'    # Total match count (session-level)
})
```

**Example:**
```
Session abc-123: 10 matching messages, latest at 10:40, project /foo
Session def-456: 5 matching messages, latest at 15:30, project /bar
Session xyz-789: 8 matching messages, latest at 09:15, project /baz
```

### 4.2 Session-Level Sorting

**Primary sort: Match count (descending)**
**Secondary sort: Timestamp (descending)**

```python
session_stats.sort_values(['count', 'timestamp'], ascending=[False, False])
```

**Example ranking:**
```
Session abc-123: 10 matches, Dec 28 10:40 → Rank 1 (most matches)
Session xyz-789: 8 matches, Dec 28 09:15  → Rank 2 (second most matches)
Session def-456: 5 matches, Dec 27 15:30  → Rank 3 (fewest matches)
```

### 4.3 Session-Level Limiting

**Limit to top N sessions** (default: 10)
```python
session_stats.head(sessions)
```

### 4.4 Message-Level Limiting (Per Session)

**For each kept session, show top M messages** (default: 5)
```python
session_msgs = df[df['session_id'] == session_id].head(messages)
```

**Example:**
```
Session abc-123 has 10 matching messages:
  Message 1: "How to implement JWT?" → SHOW (top 5)
  Message 2: "Here's the implementation..." → SHOW (top 5)
  Message 3: "What about refresh tokens?" → SHOW (top 5)
  Message 4: "Here's the refresh logic..." → SHOW (top 5)
  Message 5: "Can we add token rotation?" → SHOW (top 5)
  Message 6-10: ... → HIDE (beyond limit)

Display: "... and 5 more matches"
```

### 4.5 Message-Level Snippet Extraction

For long messages (>300 chars):
```python
if len(text) > context:
    pos = text_lower.find(query)
    if pos >= 0:
        # Extract context window around match
        before = context // 3
        after = context - before
        snippet = text[pos-before:pos+after]
```

### Output Format

```
~/project | abc-123-def-456 | 10 matches | 2024-12-28T10:40:00Z
[user] How do I implement JWT authentication?
[asst] I'll help you implement JWT auth. First...
... and 5 more matches

~/other-project | def-456-ghi | 5 matches | 2024-12-27T15:30:00Z
[user] Can you explain git rebase?
... and 2 more matches

Found matches in 2 sessions
```

---

## Summary: Session vs Message Filtering

### SESSION-LEVEL FILTERS (Remove entire sessions)

| Stage | Filter | Reason |
|-------|--------|--------|
| **Index** | Fork sessions | Temporary recall sessions |
| **Index** | Current session | Don't show your own conversation |

**When to use:** Structural exclusions where you never want ANY content from these sessions.

---

### MESSAGE-LEVEL FILTERS (Remove individual messages)

| Stage | Filter | Reason |
|-------|--------|--------|
| **Index** | Short messages (<10 chars) | Not meaningful |
| **Index** | System noise (15+ patterns) | Tool syntax, errors, IDE events |
| **Index** | Recall outputs | Previous recall results |
| **Search** | Non-matching messages | Don't match query |
| **Search** | Excluded terms | User-specified exclusions |
| **Post-Search** | Pre-recall messages | Time-based contamination |
| **Ranking** | Beyond top M per session | Display limit |

**When to use:** Quality/content filters where you want to keep the session but filter specific messages.

---

## Key Insight: Filtering Granularity

```
Session abc-123 (10 messages):
  ↓
  SESSION-LEVEL: Is this a fork session? Current session?
    YES → Exclude ENTIRE session (all 10 messages)
    NO  → Continue to message-level filtering
  ↓
  MESSAGE-LEVEL: Check each of 10 messages:
    - Is it short?
    - Does it have noise patterns?
    - Does it match the query?
    - Is it before a recall cutoff?
    - Is it in the top M for display?
  ↓
  RESULT: Maybe 5 out of 10 messages get shown
```

**Session-level is coarse (all or nothing)**
**Message-level is fine-grained (selective)**

This distinction determines:
- **Efficiency:** Session-level filters are faster (skip entire files)
- **Precision:** Message-level filters are more precise (selective exclusion)
- **Use cases:** Session-level for structural issues, message-level for content quality
