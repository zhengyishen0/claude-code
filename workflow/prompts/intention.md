# Intention Stage Prompt

Process a raw note into a task file with Intention section filled.

## Step 0: Analyze ideas

Read the note. Group related ideas, split unrelated ones.
- Related (same topic) → 1 task
- Unrelated (different topics) → multiple tasks

## Step 1: Check internal sources

- `/memory` — previous sessions
- Lessons, related .md files
- Feishu/WeChat if relevant

## Step 2: Create task file

For each task, create `vault/tasks/NNN-slug.md`:

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

## Step 3: Create resources folder if needed

Create `vault/resources/NNN-slug/` for research outputs later.

## Rules

- **Task file:** `vault/tasks/NNN-slug.md`
- **Resources:** `vault/resources/NNN-slug/`
- **status: intention**
- **submit: false**
- Update `vault/index.md`

## Output

Report how many tasks created and why grouped that way.
