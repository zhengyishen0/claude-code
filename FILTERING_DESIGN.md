# Memory Search Filtering Design

## Overview

4-stage filtering pipeline: Index → Search → Recall Cutoff → Ranking

---

## Filtering by Stage & Level

### Stage 1: Index Building

**Session-Level Filters (exclude entire sessions)**
- Fork sessions (queue-operation)
- Current session (CLAUDE_SESSION_ID)

**Message-Level Filters (exclude individual messages)**
- Short messages (<10 chars)
- Tool/system noise: `<ide_`, `<bash-`, `<function_calls>`, API errors, etc. (15+ patterns)
- Recall output summaries (`[N/M] sessionid • date`)

**Output:** `session_id \t timestamp \t type \t text \t project_path`

---

### Stage 2: Query Search

**Message-Level Filters Only**
- OR: Space-separated terms
- AND: `--require` flag (all must match)
- NOT: `--exclude` flag (none can match)

**Pipeline:** `rg OR | rg AND1 | rg AND2 | grep -v NOT`

---

### Stage 3: Recall Cutoff

**Message-Level Filters (temporal)**
- Detect recall events: `I'll search`, `memory search`, `Did you remember`, etc.
- Exclude messages at/before recall timestamp in affected sessions

**⚠️ Issue:** Too aggressive - excludes ALL prior messages, not just recall-related

---

### Stage 4: Ranking

**Session-Level Operations**
- Group messages by session
- Sort by: (1) match count DESC, (2) timestamp DESC
- Limit to top N sessions (default: 10)

**Message-Level Operations**
- Show top M messages per session (default: 5)
- Extract snippets for long messages (>300 chars)

---

## Summary Tables

### Exclusions by Stage

| Stage | Level | What Gets Excluded |
|-------|-------|-------------------|
| **Index** | Session | Fork sessions, Current session |
| **Index** | Message | Short (<10), System noise (15+ patterns), Recall outputs |
| **Search** | Message | Non-matching content, --exclude terms |
| **Recall Cutoff** | Message | Messages before recall events |
| **Ranking** | Message | Beyond top M per session |

### Current Gaps

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
