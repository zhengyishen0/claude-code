# Memory Search Filtering

## Overview

**4-stage pipeline:** Index → Search → Recall Cutoff → Ranking

**Two filtering levels:**
- **Session-Level:** Exclude entire sessions (all messages)
- **Message-Level:** Exclude individual messages within sessions

### Filtering Matrix

| Level | Stage 1: Index | Stage 2: Search | Stage 3: Recall Cutoff | Stage 4: Ranking |
|-------|---------------|-----------------|----------------------|------------------|
| **Session-Level** | Fork sessions<br>Current session | *(none)* | *(none)* | Beyond top N sessions |
| **Message-Level** | Short messages<br>System noise<br>Recall outputs | Non-matching queries<br>`--exclude` terms | Messages before recall | Beyond top M per session<br>Snippet extraction |

---

## Stage 1: Indexing

**Goal:** Build clean, searchable index from JSONL files
**Location:** `search.sh:89-161`

### Session-Level Filters

| Filter | Pattern | Reason |
|--------|---------|--------|
| **Fork sessions** | First line: `"type":"queue-operation"` | Temporary recall forks, not original work |
| **Current session** | `session_id == $CURRENT_SESSION_ID` | Don't show your own current conversation |

**Effect:** All messages from these sessions excluded

### Message-Level Filters

| Filter | Pattern | Reason |
|--------|---------|--------|
| **Short messages** | `length < 10` chars | Not meaningful |
| **System noise** | `<ide_`, `<bash-`, `<function_calls>`, API errors, etc. | Tool syntax, IDE events (15+ patterns) |
| **Recall outputs** | `^\[[0-9]+/[0-9]+]\s+[a-f0-9]{7}\s+•` | Previous recall summaries like `[1/5] abc1234 • Dec 28` |

**Effect:** Session kept, specific messages filtered

### Output Format

```tsv
session_id \t timestamp \t type \t text \t project_path
```

---

## Stage 2: Query Search

**Goal:** Find messages matching user query
**Location:** `search.sh:175-210`
**Level:** Message-Level Only

### Query Modes

| Mode | Syntax | Example |
|------|--------|---------|
| **OR** | Space-separated | `"authentication jwt"` → either term |
| **AND** | `--require` flag | `--require "implement"` → must contain |
| **NOT** | `--exclude` flag | `--exclude "test"` → must not contain |

### Pipeline

```bash
rg -i "(auth|jwt)" index.tsv  # OR: match any term
  | rg -i "implement"          # AND: must contain
  | grep -iv "test"            # NOT: must not contain
```

**Effect:** Filters individual messages that don't match query

---

## Stage 3: Recall Cutoff

**Goal:** Remove messages contaminated by previous recalls
**Location:** `search.sh:310-341`
**Level:** Message-Level (temporal)

### Detection Patterns

Searches for: `I'll search`, `memory search`, `Did you remember`, `memory recall`

### Algorithm

1. Find recall events → extract `(session_id, timestamp)` per session
2. For each message:
   - If session has recall cutoff AND message.timestamp ≤ cutoff → **EXCLUDE**
   - Otherwise → **KEEP**

**⚠️ Known Issue:** Too aggressive - excludes ALL prior messages, not just recall-related content

**Effect:** Filters messages before recall timestamp in affected sessions

---

## Stage 4: Ranking

**Goal:** Order sessions by relevance
**Location:** `format-results.py:42-96`
**Level:** Both (aggregate then limit)

### Session-Level Operations

1. **Group:** Aggregate messages by session_id
2. **Sort:** (1) match count DESC, (2) timestamp DESC
3. **Limit:** Top N sessions (default: 10)

### Message-Level Operations

1. **Limit:** Top M messages per session (default: 5)
2. **Snippet:** Extract context around query for long messages (>300 chars)

**Effect:** Filters low-ranking sessions and excess messages per session

---

## Summary Tables

### Filters by Stage and Level

| Stage | Level | What Gets Filtered |
|-------|-------|-------------------|
| **Index** | Session | Fork sessions, Current session |
| **Index** | Message | Short (<10), System noise (15+), Recall outputs |
| **Search** | Message | Non-matching content, --exclude terms |
| **Recall** | Message | Messages before recall timestamp |
| **Ranking** | Session | Beyond top N sessions |
| **Ranking** | Message | Beyond top M per session |

### Key Insight: Granularity

```
Session abc-123 (10 messages):
  ↓
  SESSION-LEVEL: Fork? Current?
    YES → Exclude ALL 10 messages
    NO  → Continue ↓
  MESSAGE-LEVEL: Check each message
    - Too short? Noise pattern? Doesn't match query?
    → Filter individually
  ↓
  RESULT: Maybe 5 of 10 messages shown
```

**Session-level is coarse (all or nothing)**
**Message-level is fine-grained (selective)**

---

## Current Gaps

**Not Excluded:**
- Low-quality messages ("ok", "thanks")
- Off-topic tangents
- Failed/aborted work
- Duplicate sessions
- Project-irrelevant results

**Missing Features:**
- Match quality scoring
- Project-aware search
- Session deduplication
- Fuzzy matching
- Semantic relevance
