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
├── tasks/                # All task files
│   ├── 001-task-name.md
│   ├── 002-another.md
│   └── ...
├── resources/            # Research outputs per task
│   ├── 001-task-name/
│   │   ├── research.md
│   │   └── screenshot.png
│   └── 002-another/
└── archive/              # Done or dropped
```

**All tasks visible at once** in `tasks/` folder.

---

## Task File Format

`tasks/NNN-slug.md`:

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
**Questions:** [If unclear]

## Assessment

**Oneliner:** [Key finding + recommendation]
**Findings:** [Research results]
**Options:** [Paths with tradeoffs]
**Recommendation:** [AI suggestion]

## Decision

**Deliverable:** [What will be done]
**Output:** [Verifiable result]
**Test:** [Checklist]
**Constraints:** [What NOT to do]

## Execution

**Outcome:** success | partial | failed | pivot
**Work Done:** [What was executed]
**Verification:** [Test results]

---

## Human Feedback

[Write here at any stage]

## Lessons
```

---

## Workflow

```
1. Human creates note in vault root
2. AI creates tasks/NNN-slug.md with Intention
3. Human reviews → sets submit: true
4. AI fills Assessment
5. Human reviews → sets submit: true
6. AI fills Decision
7. Human approves → sets submit: true
8. AI executes → fills Execution → status: done
```

---

## Status Flow

```
intention → assessment → decision → execution → done
                                            ↘ dropped
```

---

## Resources

`resources/NNN-slug/` for each task:
- Detailed research reports
- Screenshots
- API docs
- Any supporting material

Link from task: `See: [[resources/001-task-name/research.md]]`

---

## Summary

```
┌─────────────────────────────────────────────┐
│  vault/                                      │
│  ├── tasks/         ← All task files here   │
│  │   ├── 001-xxx.md                         │
│  │   └── 002-yyy.md                         │
│  └── resources/     ← Research per task     │
│      ├── 001-xxx/                           │
│      └── 002-yyy/                           │
└─────────────────────────────────────────────┘
```

**Simple. Clean. All tasks visible at once.**
