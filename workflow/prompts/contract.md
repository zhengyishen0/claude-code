# Decision Stage Prompt

Fill the Decision section in task.md based on chosen option.

## Step 1: Read context

- Read task.md Assessment section
- Note which option human chose (from feedback or checkbox)
- Read Human Feedback section

## Step 2: Fill Decision section

Update task.md:

```markdown
## Decision

**Deliverable:** [One line — what will be done]

**Output:** [What done looks like — specific, verifiable]

**Test:**
- [ ] [Verification item 1]
- [ ] [Verification item 2]

**Constraints:** [What NOT to do]

**Danger:** [What would break things — if any]

**Approval:** [Ready to execute? / Needs changes? / Drop?]
```

## Step 3: Update frontmatter

```yaml
status: decision
submit: false
```

## Rules

- **Deliverable = specific**, not vague
- **Output = verifiable**
- **Test = checkable items**
- **Constraints = what NOT to do**
- **status: decision**
- **submit: false** — human approves before execution
