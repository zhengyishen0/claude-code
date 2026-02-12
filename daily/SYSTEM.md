# IVDX Vault System

The document-based async collaboration system for human-AI work.

---

## Overview

```
I → V → D → X

I: Intention    — Agreement on what human wants (contract for research)
V: Validation   — Agreement on findings (enough info for discussion)
D: Decision     — Agreement on what to do (contract for execution)
X: Execution    — Record of what worked and what didn't
```

**Human:** Ideas + Decisions
**AI:** Research + Execution

**All output is documents. No chat responses.**

---

## File Structure

```
vault/
├── index.md                    # Overview of all tasks
├── SYSTEM.md                   # This file
├── templates/
│   ├── intention.md
│   ├── assessment.md
│   ├── contract.md
│   └── report.md
│
├── (anywhere)/                 # WATCHED — raw notes
│   └── random-idea.md          # Human dumps ideas here
│
├── active/                     # NOT watched — being processed
│   └── task-name/
│       ├── task.md             # Index for this task
│       ├── intention.1.md
│       ├── intention.2.md
│       ├── assessment.1.md
│       ├── contract.1.md
│       └── report.1.md
│
└── archive/                    # Done or dropped
    └── old-task/
```

---

## Document Types

| Stage | File | Purpose |
|-------|------|---------|
| I | `intention.N.md` | Agreement on what human wants — contract for research |
| V | `assessment.N.md` | Agreement on findings — enough info for discussion |
| D | `contract.N.md` | Agreement on what to do — contract for execution |
| X | `report.N.md` | Record of what worked and what didn't |

All deliverables use `.N.md` numbering (1, 2, 3...) for versioning.

---

## Universal Document Pattern

Every document follows this structure:

```markdown
## Summary
[One-liner — extremely concise]

## Key Questions
1. First question?
   - [ ] option a
   - [ ] option b
   - [ ] other: ___

2. Second question?
   - [ ] option a
   - [ ] option b
   - [ ] other: ___

## Human Feedback
(write here)

---

[Document-specific sections...]

---

## Lessons Applied
- [[lesson-name]] — how it was applied

## Lessons Proposed
- [ ] WHEN ... → DO ... → BECAUSE ...
- [ ] WHEN ... → DO ... → BECAUSE ...
```

---

## Frontmatter: Submit Checkbox

```yaml
---
submit: false
---
```

| Value | Meaning |
|-------|---------|
| `submit: false` | AI's draft, waiting for human |
| `submit: true` | Human done editing, AI should process |

**Flow:**
1. AI creates doc → `submit: false`
2. Human reads, checks options, writes feedback → sets `submit: true`
3. AI sees `submit: true` → processes → creates new version with `submit: false`

---

## task.md (Task Index)

**Purpose:** Index file linking all deliverables for a task.

### Frontmatter

```yaml
---
type: task
status: intention | assessment | decision | execution | done | dropped
workdir: /path/to/codebase
created: 2025-02-11
session_id:
---
```

### Sections

```markdown
## Idea
[Original raw note — copied verbatim]

## Intentions
- [[intention.1]]
- [[intention.2]]

## Assessments
- [[assessment.1]]

## Contracts
- [[contract.1]]

## Reports
- [[report.1]]
```

---

## intention.N.md

**Purpose:** Agreement on what human wants — the contract for doing research.

### Frontmatter

```yaml
---
type: intention
task: "[[task]]"
round: 1
status: draft | confirmed
submit: false
---
```

### Sections

```markdown
## Summary
[One-liner: What you want and why]

## Key Questions
1. Is this understanding correct?
   - [ ] Yes, proceed
   - [ ] Partially, see feedback
   - [ ] No, see feedback
   - [ ] other: ___

2. Ready for assessment?
   - [ ] Yes
   - [ ] Need more clarification first
   - [ ] other: ___

## Human Feedback
(write here)

---

## What
[The request]

## Why
[Motivation, context]

## Success
[What success looks like]

## Not
[Out of scope]

---

## Lessons Applied
- [[lesson-name]] — how it was applied

## Lessons Proposed
- [ ] WHEN ... → DO ... → BECAUSE ...
```

---

## assessment.N.md

**Purpose:** Agreement on findings — enough info for decision discussion.

### Frontmatter

```yaml
---
type: assessment
task: "[[task]]"
intention: "[[intention.1]]"
round: 1
confidence: high | medium | low
status: draft | confirmed
submit: false
---
```

### Sections

```markdown
## Summary
[One-liner: Key finding + recommendation]

## Key Questions
1. Agree with the findings?
   - [ ] Yes
   - [ ] Partially, see feedback
   - [ ] No, see feedback
   - [ ] other: ___

2. Which option to pursue?
   - [ ] Option A
   - [ ] Option B
   - [ ] Option C
   - [ ] other: ___

3. Ready for contract?
   - [ ] Yes
   - [ ] Need more research
   - [ ] other: ___

## Human Feedback
(write here)

---

## Context
[What we know]

## Findings
[Research results]

## Implications
[What this affects]

## Options
[Multiple paths with tradeoffs]

## Recommendation
[What AI suggests]

---

## Lessons Applied
- [[lesson-name]] — how it was applied

## Lessons Proposed
- [ ] WHEN ... → DO ... → BECAUSE ...
```

---

## contract.N.md

**Purpose:** Agreement on what to do — the contract for execution.

### Frontmatter

```yaml
---
type: contract
task: "[[task]]"
assessment: "[[assessment.1]]"
version: 1
status: draft | signed | dropped
submit: false
---
```

### Sections

```markdown
## Summary
[One-liner: The deliverable]

## Key Questions
1. Ready to sign?
   - [ ] Yes, execute this
   - [ ] Need changes, see feedback
   - [ ] Drop this task
   - [ ] other: ___

## Human Feedback
(write here)

---

## Task
[One line deliverable]

## Input
[Starting point]

## Output
[What done looks like]

## Test
[How to verify]

## Constraints
[What NOT to do]

## Danger
[What would break things]

---

## Lessons Applied
- [[lesson-name]] — how it was applied
```

---

## report.N.md

**Purpose:** Record of execution — what worked and what didn't.

### Frontmatter

```yaml
---
type: report
task: "[[task]]"
contract: "[[contract.1]]"
attempt: 1
outcome: success | partial | failed | pivot
submit: false
---
```

### Sections

```markdown
## Summary
[One-liner: Outcome]

## Key Questions
1. Accept this result?
   - [ ] Yes, mark done
   - [ ] Retry with adjustments
   - [ ] Pivot, need new approach
   - [ ] other: ___

## Human Feedback
(write here)

---

## Work Done
[What was executed]

## What Worked
[Successes]

## What Didn't
[Failures, issues]

## Verification
[Contract tests: pass/fail]

---

## Lessons Proposed
- [ ] WHEN ... → DO ... → BECAUSE ...
```

---

## Status Flow

```
task.md status:

intention → assessment → decision → execution → done
                                             ↘ dropped
```

| Transition | Trigger |
|------------|---------|
| → intention | Raw note detected |
| → assessment | intention confirmed |
| → decision | assessment confirmed |
| → execution | contract signed |
| → done | report accepted |
| → dropped | Human chooses drop at any stage |

---

## AI Auto-Proceed Logic

AI can auto-proceed to next stage when:
- `submit: true`
- All questions answered (boxes checked)
- No blocking feedback
- Previous stage confirmed/signed

AI can auto-sign contract when:
- Assessment confirmed
- All contract fields clear
- No danger flags

---

## Human Workflow

1. See doc in Obsidian
2. Read **Summary**
3. Answer **Key Questions** (check boxes)
4. Write in **Human Feedback** if needed
5. Set `submit: true` in frontmatter
6. AI processes → new version appears

---

## Lessons System

### Format

```
WHEN [situation] → DO [action] → BECAUSE [reason]
```

### In Documents

**Lessons Applied:**
```markdown
## Lessons Applied
- [[lesson-name]] — how it was applied
```

**Lessons Proposed:**
```markdown
## Lessons Proposed
- [ ] WHEN editing config files → DO backup first → BECAUSE easy to break
- [ ] WHEN API returns 429 → DO add retry with backoff → BECAUSE rate limits
```

### Human Confirms Lessons

- Human checks the box → lesson becomes active for future use
- Human leaves unchecked → lesson stays proposed

### AI Auto-Confirm

If a proposed lesson appears multiple times (unchecked):
- AI tracks occurrences
- After N occurrences (e.g., 3), AI auto-checks and notes: `(auto-confirmed by AI after 3 occurrences)`

---

## Archive Workflow

Human sets in task.md:
```yaml
status: done      # or: dropped
```

AI sees status change → moves entire task folder to `archive/`

---

## Summary

```
┌─────────────────────────────────────────────────────────┐
│  Human dumps idea anywhere in vault                     │
│                    ↓                                    │
│  AI creates task folder + intention.1.md                │
│                    ↓                                    │
│  Human reviews, submits feedback                        │
│                    ↓                                    │
│  AI creates assessment.1.md                             │
│                    ↓                                    │
│  Human reviews, submits feedback                        │
│                    ↓                                    │
│  AI creates contract.1.md                               │
│                    ↓                                    │
│  Human signs (or AI auto-signs if clear)                │
│                    ↓                                    │
│  AI executes, creates report.1.md                       │
│                    ↓                                    │
│  Human accepts → done | retry → report.2.md             │
│                    ↓                                    │
│  Lessons captured for future                            │
└─────────────────────────────────────────────────────────┘
```

**One gate:** Contract signing (human or AI if clear)
**Worst case:** Drop the work. Never break anything.
