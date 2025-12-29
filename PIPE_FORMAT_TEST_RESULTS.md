# Pipe Format Test Results

## New Syntax

**Format:** `"a1|a2|a3 b1|b2|b3"`
- `|` (pipe) = OR within group
- ` ` (space) = AND between groups

**Result:** (a1 OR a2 OR a3) AND (b1 OR b2 OR b3)

## Test Results: Before vs After

| Scenario | Old Format (--require) | Results | New Format (pipe) | Results |
|----------|------------------------|---------|-------------------|---------|
| 1. Simple | `"chrome"` | ✅ 3 sessions | `"chrome"` | ✅ 3 sessions |
| 2. Auth | `"JWT OAuth authentication" --require "implemented created built added"` | ❌ 0 sessions | `"JWT\|OAuth\|authentication implemented\|created\|built\|added"` | ✅ 2 sessions |
| 3. Error fix | `"error bug fix" --require "fixed resolved patched implemented"` | ❌ 0 sessions | `"error\|bug\|fix fixed\|resolved\|patched\|implemented"` | ✅ 3 sessions |
| 4. Chrome CDP | N/A | N/A | `"chrome\|browser CDP implement\|build"` | ✅ 3 sessions |

## Key Improvements

### 1. **Simpler Syntax**
**Before (confusing):**
```bash
memory search "JWT OAuth authentication" --require "implemented created built added"
# What does this mean? Unclear to LLMs
```

**After (clear):**
```bash
memory search "JWT|OAuth|authentication implemented|created|built|added"
# Means: (JWT OR OAuth OR authentication) AND (implemented OR created OR built OR added)
```

### 2. **Matches Mental Model**
Haiku's thinking:
- "I want JWT OR OAuth OR authentication topics"
- "AND must have implemented OR created OR built OR added"

Syntax directly maps to thinking: `"topic1|topic2|topic3 action1|action2|action3"`

### 3. **No More Empty Results**
**Problem with old format:**
- `--require "implemented created built added"` meant ALL FOUR words
- Sessions only have ONE verb → 0 results

**Solution with pipe format:**
- `"implemented|created|built|added"` means ANY ONE word
- Sessions with ANY verb → matches found

### 4. **Removed --require and --exclude Flags**
**Simplification:**
- No flags needed
- Everything in one query string
- Pipe for OR, space for AND

**Note:** We removed --exclude entirely (as discussed, users can't predict noise when they don't know the topic)

## Examples

### Example 1: Chrome Automation
```bash
memory search "chrome|browser|automation implement|build|create"
```
Means:
- (chrome OR browser OR automation) AND (implement OR build OR create)

### Example 2: Authentication
```bash
memory search "JWT|OAuth|authentication implement"
```
Means:
- (JWT OR OAuth OR authentication) AND implement

### Example 3: Error Fixing
```bash
memory search "error|bug fix|solve|patch"
```
Means:
- (error OR bug) AND (fix OR solve OR patch)

### Example 4: Simple Query (no pipes)
```bash
memory search "screenshot"
```
Means:
- screenshot (simple term match)

## Implementation Details

**Parsing logic:**
1. Split query by spaces → AND groups
2. For each group, split by pipes → OR terms
3. Build regex: `(term1|term2|term3)` for each group
4. Chain with `rg` pipeline: `rg '(a1|a2)' | rg '(b1|b2)'`

**Code change:**
- Removed `--require` and `--exclude` parsing
- Removed separate OR/REQUIRE/EXCLUDE logic
- Unified into single pipe-based parser

## Next Steps

1. ✅ Implementation works
2. ✅ Tests pass
3. ⏳ User approval needed
4. ⏳ Update memory/run.sh help text to match
5. ⏳ Merge to main

## Questions

1. Should we keep the underscore phrase support (`reset_windows` → "reset windows")?
2. Do we want --recall integration (seems orthogonal to search syntax)?
3. Any edge cases to test?
