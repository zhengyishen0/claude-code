# Assessment Stage Prompt

Intention is confirmed. Do external research and fill in the template below.

## Step 1: Read context

- Read the confirmed intention.N.md
- Read any human feedback
- Note what research is needed

## Step 2: Do research

- Web search for current information
- Read relevant documentation
- Gather facts, not opinions

## Step 3: Create assessment.N.md

Fill in this template exactly:

```markdown
---
type: assessment
task: "[[task]]"
intention: "[[intention.N]]"
round: 1
status: draft | confirmed
confidence: high | medium | low
submit: false
created: YYYY-MM-DD
---

## Oneliner

[Key finding + recommendation, one sentence]

## Key Questions

(only if decision needed — skip if recommendation is clear)

1. Which option?
   - [ ] Option A
   - [ ] Option B
   - [ ] other: ___

## Human Feedback

(leave empty for human)

---

## Context

[What we already knew]

## Findings

[Research results — facts, not fluff]

## Implications

[What this affects]

## Options

[Paths with tradeoffs]

## Recommendation

[What AI suggests and why]

---

## Lessons Applied

## Lessons Proposed
```

## Rules

- **Fill template EXACTLY** — don't add/remove sections
- **Oneliner** — key finding + recommendation, one sentence
- **Key Questions** — only if human needs to choose between options
- **Findings** — concrete facts from research
- **Options** — real tradeoffs, not fluff
- **submit: false** — always, human reviews first
- Update task.md Assessments section with link

## After Writing

Commit: `jj new -m "[assessment] NNN-slug: key finding"`
