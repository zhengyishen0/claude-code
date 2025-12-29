# Ranking Validation Experiment

## Objective

Test whether the current memory search ranking algorithm produces sensible results for recall quality. The goal is to ensure the top 10 sessions are likely to provide good answers when recalled in parallel.

## Current Ranking Algorithm

**Location:** `claude-tools/memory/format-results.py:50`

```python
session_stats.sort_values(['count', 'timestamp'], ascending=[False, False])
```

**Logic:**
1. Primary: Most matches first (sessions with highest keyword occurrence)
2. Secondary: Most recent first (if match counts are equal)

## Experiment Design

### Test Queries

Select diverse query types that represent real usage:

1. **Tool Implementation** - "chrome automation"
   - Looking for: Sessions that built/debugged the chrome tool
   - Expect: Deep technical sessions to rank high

2. **Feature Discussion** - "memory search ranking"
   - Looking for: Sessions that designed/discussed ranking logic
   - Expect: Design conversations to rank high

3. **Bug Investigation** - "session filtering"
   - Looking for: Sessions that fixed filtering bugs
   - Expect: Bug fix sessions to rank high

4. **Conceptual Topic** - "context management AI agents"
   - Looking for: Sessions with architectural discussions
   - Expect: Design sessions to rank high

5. **Specific Technical Term** - "recall cutoff"
   - Looking for: Sessions that implemented/discussed this feature
   - Expect: Implementation sessions to rank high

### Validation Process

For each query:

1. **Run Search**
   ```bash
   claude-tools memory search "<query>" --sessions 15
   ```

2. **Manual Assessment (Prediction)**
   - Review each of the top 15 sessions
   - For each session, assess:
     - **Focus:** Was this topic central to the session? (High/Medium/Low)
     - **Depth:** How deep was the discussion? (Deep/Medium/Shallow)
     - **Work Done:** Was actual work done on this topic? (Yes/No)
     - **Predicted Quality:** Would recall likely give a quality answer? (High/Medium/Low/None)

3. **Actual Recall (Verification)**
   - Run parallel recall on all 15 sessions:
     ```bash
     claude-tools memory recall "session1:How was <topic> implemented?" "session2:..." ...
     ```
   - For each answer, record:
     - **Actual Quality:** Did it provide useful information? (High/Medium/Low/None)
     - **Answer Type:** Deep technical / Summary / "No information" / Other
     - **Surprise Factor:** Did it match prediction? (Better/Same/Worse)

4. **Compare Rankings**
   - Current algorithm ranking (1-15)
   - Manual "ideal" ranking based on ACTUAL recall quality (1-15)
   - Prediction accuracy (how well did I assess from matches alone?)
   - Identify mismatches and patterns

5. **Analysis**
   - Do high-match-count sessions correlate with quality answers?
   - Are there sessions that rank high but said "I don't have information"?
   - Are there low-ranked sessions that gave surprisingly good answers?
   - Did manual assessment (viewing matches) predict recall quality accurately?

### Success Criteria

**Good Ranking (Current Algorithm Works):**
- Top 10 sessions are "High" or "Medium" recall probability
- At least 7/10 would provide quality answers
- Few "None" probability sessions in top 10

**Poor Ranking (Need Improvement):**
- Multiple "Low" or "None" probability sessions in top 10
- High-quality sessions ranked 11-15 (outside parallel recall window)
- Clear pattern showing match count doesn't predict recall quality

## Data Collection Template

For each query, create a table:

| Rank | Session ID | Matches | Focus | Depth | Work | Pred Quality | Actual Quality | Answer Type | Surprise | Notes |
|------|------------|---------|-------|-------|------|--------------|----------------|-------------|----------|-------|
| 1 | abc123f | 180 | High | Deep | Yes | High | High | Deep technical | Same | Entire session on chrome impl |
| 2 | def456a | 150 | Med | Med | Yes | Med | Low | "No info" | Worse | Mixed topics, recall showed limited knowledge |
| 3 | ghi789b | 120 | Low | Shallow | No | Low | None | "No info" | Same | Quick question only |
| ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |

**Rankings:**
- **Current Algorithm:** 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
- **Ideal (based on actual recall):** [Reorder by actual quality]
- **Prediction Accuracy:** X/15 correct quality predictions

## Analysis Questions

After completing all queries:

1. **Match Count Correlation:**
   - Do high match counts predict high recall probability?
   - Are there counter-examples (high matches, low quality)?

2. **Recency Bias:**
   - Do recent sessions rank appropriately?
   - Are old but valuable sessions being buried?

3. **False Positives:**
   - Which sessions rank high but would give "no information"?
   - What patterns do they share?

4. **False Negatives:**
   - Which sessions rank low but should rank high?
   - Why are they being under-ranked?

5. **Actionable Insights:**
   - If ranking is poor, what single metric would improve it most?
   - Match density (matches / total_messages)?
   - Code presence?
   - Tool usage signals?

## Next Steps

Based on findings:

**If ranking is good:**
- ✅ Keep current algorithm
- Document validation results
- Monitor over time

**If ranking needs improvement:**
- Identify the most impactful signal (density, code, etc.)
- Implement simplest improvement
- Re-validate with same queries

---

## Experiment Log

_Validation results will be added here for each query_
