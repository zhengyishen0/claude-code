# Execution Stage Prompt

Decision is approved. Do the work and fill Execution section.

## Step 1: Read Decision

- Read task.md Decision section
- Note: Deliverable, Output, Test, Constraints, Danger

## Step 2: Execute

- Do the work as specified
- Stay in scope — only what Decision says
- Follow Constraints
- If blocked, stop — don't force through

## Step 3: Verify

- Check each Test item
- Does output match?
- Were Constraints respected?

## Step 4: Fill Execution section

Update task.md:

```markdown
## Execution

**Outcome:** success | partial | failed | pivot

**Work Done:** [What was executed]

**Verification:**
| Test | Result |
|------|--------|
| [from Decision] | ✅ / ❌ |

**What Worked:** [Successes]

**What Didn't:** [Issues, if any]

**Next:** [Accept? Retry? Pivot?]
```

## Step 5: Update frontmatter

If successful:
```yaml
status: done
submit: false
```

If needs retry/pivot:
```yaml
status: execution
submit: false
```

## Outcome Values

- `success` — all tests pass
- `partial` — some done, needs more
- `failed` — blocked, can't complete
- `pivot` — discovered better approach

## Rules

- **Be honest** — don't hide problems
- **Verification table** — check each test
- **status: done** if success, otherwise stay in execution
- **submit: false**
