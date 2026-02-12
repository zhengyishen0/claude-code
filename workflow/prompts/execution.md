# Execution Stage Prompt

Decision is approved. Do the work and fill Execution section.

## Step 1: Read Decision

- Read task file Decision section
- Note: Deliverable, Output, Test, Constraints, Danger

## Step 2: Execute

- Do the work as specified
- Stay in scope
- Follow Constraints
- If blocked, stop

## Step 3: Verify

- Check each Test item
- Does output match?

## Step 4: Fill Execution section

Update task file:

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

If needs retry:
```yaml
status: execution
submit: false
```

## Rules

- **Be honest**
- **status: done** if success
- **submit: false**
