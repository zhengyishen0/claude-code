# Execution Stage Prompt

Contract is signed. Do the work and fill in the report template below.

## Step 1: Read contract

- Read the signed contract.N.md
- Note Task, Output, Test, Constraints, Danger

## Step 2: Execute

- Do the work as specified
- Stay in scope — only what contract says
- Follow constraints — respect "NOT to do"
- If blocked, stop — don't force through
- Record progress with jj commits

## Step 3: Verify

- Check each Test item from contract
- Does output match contract's Output?
- Were Constraints respected?
- Any Danger items triggered?

## Step 4: Create report.N.md

Fill in this template exactly:

```markdown
---
type: report
task: "[[task]]"
contract: "[[contract.N]]"
attempt: 1
outcome: success | partial | failed | pivot
submit: false
created: YYYY-MM-DD
---

## Oneliner

[Outcome, one sentence]

## Key Questions

1. Accept result?
   - [ ] Yes, mark done
   - [ ] Retry with adjustments
   - [ ] Pivot — need new approach
   - [ ] other: ___

## Human Feedback

(leave empty for human)

---

## Work Done

[What was executed]

## Verification

| Test | Result |
|------|--------|
| [from contract] | ✅ / ❌ |

## What Worked

## What Didn't

---

## Lessons Proposed
```

## Outcome Values

- `success` — all tests pass
- `partial` — some done, needs more
- `failed` — blocked, can't complete
- `pivot` — discovered better approach

## Rules

- **Fill template EXACTLY** — don't add/remove sections
- **Oneliner** — outcome in one sentence
- **Verification** — copy tests from contract, mark pass/fail
- **Be honest** — don't hide problems
- **submit: false** — always, human reviews first
- Update task.md Reports section with link

## After Writing

Commit: `jj new -m "[execution] NNN-slug: outcome"`
