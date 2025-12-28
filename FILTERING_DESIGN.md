# Memory Search Filtering Design Report

## Overview

The memory search tool uses a **multi-stage filtering pipeline** to exclude irrelevant content and surface the most relevant sessions. This report documents the current design and identifies areas for enhancement.

---

## Current Filtering Stages

### Stage 1: Index Building (Noise Reduction)

**Location:** `search.sh:89-161` (in `build_full_index()` and `update_index()`)

**Exclusions at index time:**

1. **Fork sessions** (line 94)
   - Pattern: Files starting with `queue-operation` event
   - Reason: These are temporary forked sessions (e.g., memory recall forks)

2. **Short messages** (line 109)
   - Pattern: `length < 10` characters
   - Reason: Too short to be meaningful

3. **Tool/system noise** (line 110)
   - Patterns excluded:
     - `<ide_` - IDE events (file open, close, etc.)
     - `[Request interrupted` - Interrupted requests
     - `New environment` - Environment messages
     - `API Error` - API errors
     - `Limit reached` - Rate limit messages
     - `Caveat:` - System caveats
     - `<bash-` - Bash tool result markers
     - `<function_calls`, `<invoke>`, `</invoke>`, `<parameter>`, etc. - XML tool call syntax

4. **Recall output patterns** (line 112)
   - Pattern: `^\[[0-9]+/[0-9]+]\s+[a-f0-9]{7}\s+•`
   - Example: `[1/5] abc1234 • Dec 28`
   - Reason: These are outputs from previous memory recalls showing session summaries

5. **Current session** (line 116) - **NEW**
   - Pattern: `$session_id == $CURRENT_SESSION_ID`
   - Reason: Exclude the session you're currently in

**Index Format:**
```
session_id \t timestamp \t type \t text \t project_path
```

---

### Stage 2: Query Search (Content Matching)

**Location:** `search.sh:263-301`

**Query modes:**
- **OR terms**: Space-separated words in first argument
  - Example: `"authentication jwt"` → matches authentication OR jwt
- **AND terms**: `--require` flag
  - Example: `--require "implement"` → must contain "implement"
  - Multiple terms: each creates a separate filter (all must match)
- **NOT terms**: `--exclude` flag
  - Example: `--exclude "test"` → must not contain "test"

**Search pipeline:**
```bash
rg OR_PATTERN index.tsv | rg REQUIRE_1 | rg REQUIRE_2 | grep -v EXCLUDE_1
```

---

### Stage 3: Post-Search Filtering (Recall Cutoff)

**Location:** `search.sh:310-341`

**Recall cutoff logic:**

When a session contains evidence of memory recall usage, exclude all messages **at or before** that recall event.

**Detection patterns:**
- `I'll search`
- `memory search`
- `Did you remember.*talked about`
- `go back to a memory`
- `memory recall`

**Why?** If a session already used memory recall, the earlier messages might be based on recalled information rather than original work, so they're less valuable to show.

**Algorithm:**
1. Find all lines matching recall patterns → extract `(session_id, timestamp)` pairs
2. For each result line:
   - If its session has a recall cutoff timestamp
   - AND its timestamp ≤ cutoff → exclude it
   - Otherwise → keep it

---

### Stage 4: Ranking & Presentation

**Location:** `format-results.py:42-96`

**Ranking strategy:**

1. **Group by session** (pandas groupby)
2. **Sort by relevance** (line 50):
   - Primary: **match count** (descending) - sessions with more matches rank higher
   - Secondary: **timestamp** (descending) - newer sessions rank higher when tied
3. **Limit to top N sessions** (default: 10)

**Presentation per session:**
- Show up to N messages (default: 5)
- For long messages (>300 chars), extract snippet around query term
- Show total match count: `"... and X more matches"`

---

## Problems with Current Design

### Problem 1: Irrelevant Sessions Getting Through

**Issue:** Sessions might match search terms but not be truly relevant.

**Examples:**
- Session mentions "chrome" in passing but is about something else
- Session has many low-quality matches (e.g., just saying "I'll use Chrome")

**Current mitigation:** None beyond basic noise filtering

**Missing:**
- Semantic relevance scoring
- Context window analysis (matches near each other = more relevant)
- Quality weighting (user messages vs assistant acknowledgments)

---

### Problem 2: Recall Cutoff Too Aggressive

**Issue:** The recall cutoff excludes ALL messages before recall, even if they're valuable.

**Example:**
```
10:00 - User asks about authentication
10:05 - Claude implements JWT auth
10:10 - Claude uses memory recall for something unrelated
```
The valuable JWT work at 10:05 gets excluded because recall happened at 10:10.

**Better approach:** Only exclude recall-related messages, not all prior work

---

### Problem 3: No Deduplication of Similar Sessions

**Issue:** Multiple sessions about the same topic might all appear.

**Current mitigation:** None

**Missing:**
- Session similarity detection
- Preference for most recent or most complete session on a topic

---

### Problem 4: Ranking Prioritizes Quantity Over Quality

**Issue:** Sessions with many weak matches rank higher than sessions with few strong matches.

**Example:**
- Session A: 10 passing mentions of "chrome"
- Session B: 2 in-depth implementations using Chrome DevTools

Session A ranks higher due to match count, but Session B is more valuable.

**Missing:**
- Match strength scoring (context, proximity, density)
- User message vs assistant message weighting
- Code block detection (technical sessions rank higher)

---

### Problem 5: No Project/Context Awareness

**Issue:** Searches across all projects without project-specific filtering.

**Missing:**
- Current project preference (search current project first)
- Project similarity (prefer sessions in similar tech stacks)
- Temporal locality (recent sessions in current project)

---

## Index-Time Filtering Coverage

**Good coverage for:**
- ✅ System noise (tool calls, errors, IDE events)
- ✅ Fork sessions
- ✅ Recall outputs (session summaries)
- ✅ Current session (NEW)

**Missing coverage for:**
- ❌ Low-quality user messages ("ok", "thanks", "yes")
- ❌ Repetitive assistant acknowledgments ("I'll help with that")
- ❌ Off-topic tangents within sessions
- ❌ Failed/aborted work
- ❌ Test/debugging messages

---

## Query-Time Filtering Coverage

**Good coverage for:**
- ✅ OR search (space-separated terms)
- ✅ AND search (--require flag)
- ✅ NOT search (--exclude flag)
- ✅ Phrase matching (underscore support)
- ✅ Case-insensitive search

**Missing coverage for:**
- ❌ Fuzzy matching (typos, variations)
- ❌ Synonym expansion
- ❌ Stemming (search, searching, searched)
- ❌ Multi-language code matching (same concept in different languages)

---

## Recommendations for Enhancement

### High Priority

1. **Improve recall cutoff logic**
   - Only exclude messages mentioning the recalled topic
   - Use sliding window around recall event instead of hard cutoff

2. **Add match quality scoring**
   - Weight matches by context (code blocks, headings, etc.)
   - Penalize weak matches (single word in long message)
   - Boost matches with clustering (multiple terms near each other)

3. **Better noise filtering at index time**
   - Filter low-quality messages ("ok", "sure", "thanks")
   - Detect failed/aborted work patterns
   - Identify test/debug sessions

### Medium Priority

4. **Project-aware search**
   - Add `--project <path>` flag to filter by project
   - Add `--current-project` flag (default behavior?)
   - Show project context in results

5. **Session deduplication**
   - Detect similar sessions (LSH or embedding similarity)
   - Prefer most recent/complete version

### Low Priority

6. **Semantic enhancements**
   - Fuzzy matching for typos
   - Synonym expansion
   - Stemming support

---

## Current Exclusion Summary

**At index time, we EXCLUDE:**
1. Fork sessions (queue-operation)
2. Messages <10 chars
3. Tool/system noise (15+ patterns)
4. Recall output summaries
5. Current session (NEW)

**At search time, we EXCLUDE:**
- Terms via `--exclude` flag

**After search, we EXCLUDE:**
- Messages before recall events in affected sessions

**We DO NOT exclude:**
- Low-quality conversational messages
- Off-topic tangents
- Failed work
- Similar/duplicate sessions
- Project-irrelevant results
