# Intention Stage Prompt

Process a raw note into task.md with Intention section filled.

## Step 0: Analyze ideas

Read the note. Group related ideas, split unrelated ones.
- Related (same topic) → 1 task
- Unrelated (different topics) → multiple tasks

**Examples:**
```
研究Cursor和Aider → 1 task (both AI tools)
研究tailscale / 学日语 / 整理文档 → 3 tasks (unrelated)
买机票 / 订酒店 / 规划行程 → 1 task (all trip planning)
```

## Step 1: Check internal sources

- `/memory` — previous sessions
- Lessons, related .md files
- Feishu/WeChat if relevant

## Step 2: Create task.md

For each task, create `vault/active/NNN-slug/task.md`:

```markdown
---
type: task
status: intention
submit: false
created: YYYY-MM-DD
---

## Idea

[Raw note verbatim for this task]

## Intention

**Oneliner:** [One sentence summary]

**What:** [The request]

**Why:** [Motivation]

**Success:** [What done looks like]

**Not:** [Out of scope]

**Questions:** [Only if genuinely unclear, otherwise "None"]

## Assessment

(pending)

## Decision

(pending)

## Execution

(pending)

---

## Human Feedback

## Lessons
```

## Step 3: Create resources folder

Create `vault/active/NNN-slug/resources/` for research outputs later.

## Rules

- **Group intelligently**
- **status: intention**
- **submit: false**
- Update `vault/index.md`

## Output

Report: how many tasks, what's in each, why grouped.
