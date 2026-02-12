# IVDX Vault System

Document-based async collaboration for human-AI work.

---

## Overview

```
I → V → D → X

I: Intention   — What human wants
V: Validation  — AI research findings
D: Decision    — What to do
X: Execution   — What happened
```

**Human:** Ideas + Decisions
**AI:** Research + Execution

---

## File Structure

```
vault/
├── index.md              # Overview of all tasks
├── active/
│   └── task-name/
│       ├── task.md       # Main doc (all stages in one file)
│       └── resources/    # Research outputs, screenshots, etc.
└── archive/              # Done or dropped
```

**One file per task.** Stages are sections, not separate files.

---

## task.md Format

```markdown
---
type: task
status: intention | assessment | decision | execution | done | dropped
submit: false
created: YYYY-MM-DD
---

## Idea

[Original raw note — verbatim]

## Intention

**Oneliner:** [One sentence]
**What:** [The request]
**Why:** [Motivation]
**Success:** [What done looks like]
**Not:** [Out of scope]
**Questions:** [If unclear, otherwise "None"]

## Assessment

**Oneliner:** [Key finding + recommendation]
**Findings:** [Research results]
**Options:** [Paths with tradeoffs]
**Recommendation:** [AI suggestion]
**Questions:** [If decision needed, otherwise "None"]

## Decision

**Deliverable:** [What will be done]
**Output:** [Verifiable result]
**Test:** [Checklist]
**Constraints:** [What NOT to do]
**Danger:** [What would break things]

## Execution

**Outcome:** success | partial | failed | pivot
**Work Done:** [What was executed]
**Verification:** [Test results]
**What Worked/Didn't:** [Learnings]

---

## Human Feedback

[Write here at any stage]

## Lessons
```

---

## Workflow

```
1. Human creates note in vault root
2. AI detects → creates task.md with Intention filled
3. Human reviews → sets submit: true
4. AI fills Assessment → sets submit: false
5. Human reviews → sets submit: true
6. AI fills Decision → sets submit: false
7. Human approves → sets submit: true
8. AI executes → fills Execution → status: done
```

---

## Status Flow

```
intention → assessment → decision → execution → done
                                            ↘ dropped
```

| Status | Meaning |
|--------|---------|
| intention | AI understanding, waiting for confirm |
| assessment | AI research done, waiting for review |
| decision | Plan ready, waiting for approval |
| execution | Work done, waiting for accept |
| done | Complete |
| dropped | Abandoned |

---

## Submit Flag

```yaml
submit: false  # AI's turn complete, human reviewing
submit: true   # Human done, AI should proceed
```

---

## Resources Folder

`task-name/resources/` for:
- Detailed research reports
- Screenshots
- API documentation
- Any supporting material

Link from task.md: `See: [[resources/research.md]]`

---

## Human Workflow

1. See task.md in Obsidian
2. Read current stage section
3. Write in **Human Feedback** if needed
4. Set `submit: true`
5. AI proceeds → new section filled

---

## Summary

```
┌─────────────────────────────────────────────┐
│  Human drops idea anywhere in vault          │
│                  ↓                           │
│  AI creates task.md with Intention           │
│                  ↓                           │
│  Human reviews, sets submit: true            │
│                  ↓                           │
│  AI fills Assessment (research)              │
│                  ↓                           │
│  Human reviews, sets submit: true            │
│                  ↓                           │
│  AI fills Decision (plan)                    │
│                  ↓                           │
│  Human approves, sets submit: true           │
│                  ↓                           │
│  AI executes, fills Execution                │
│                  ↓                           │
│  Human accepts → done                        │
└─────────────────────────────────────────────┘
```

**One file. Four stages. Simple.**
