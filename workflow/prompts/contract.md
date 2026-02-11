# Contract Stage Prompt

Assessment is confirmed. Draft the execution contract by filling in the template below.

## Step 1: Read context

- Read the confirmed assessment.N.md
- Note which option human chose
- Read any human feedback

## Step 2: Create contract.N.md

Fill in this template exactly:

```markdown
---
type: contract
task: "[[task]]"
assessment: "[[assessment.N]]"
version: 1
status: draft
submit: false
created: YYYY-MM-DD
---

## Oneliner

[The deliverable, one sentence]

## Key Questions

1. Ready to execute?
   - [ ] Yes, sign it
   - [ ] Need changes — see feedback
   - [ ] Drop this task
   - [ ] other: ___

## Human Feedback

(leave empty for human)

---

## Task

[One line deliverable]

## Input

[Starting point]

## Output

[What done looks like — specific, verifiable]

## Test

- [ ] ...
- [ ] ...

## Constraints

[What NOT to do]

## Danger

[What would break things]

---

## Lessons Applied
```

## Rules

- **Fill template EXACTLY** — don't add/remove sections
- **Oneliner** — the deliverable, one sentence
- **Task** — specific, not vague
- **Output** — verifiable, how do we know it's done?
- **Test** — concrete checkable items
- **Constraints** — what NOT to do
- **Danger** — what would break things
- **status: draft** — always, human signs
- **submit: false** — always, human reviews first
- Update task.md Contracts section with link

## After Writing

Commit: `jj new -m "[contract] NNN-slug: deliverable"`
