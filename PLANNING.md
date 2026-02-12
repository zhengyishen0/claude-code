# Plan Mode in Workflow

## What Plan Mode Does

Claude Code's built-in contract phase:
- Explores codebase, designs approach
- Writes plan to a file
- User approves before execution
- Built into every session — no extra tooling

## When Is a Plan Needed?

| Scope | Example | Plan? |
|-------|---------|-------|
| One-liner | Fix typo, rename variable | No |
| Small task | Add a field, tweak logic | No |
| Medium change | New script, refactor module | Maybe |
| Heavy change | New skill, architecture shift | Yes |
| Risky/irreversible | Data migration, API change | Yes |

The trigger isn't size — it's **reversibility and ambiguity**.
If you can undo it easily or the path is obvious, skip the plan.

## Soft vs Hard

| Approach | Meaning | Best For |
|----------|---------|----------|
| Soft | AI decides when to plan | Sync sessions (human is watching) |
| Hard | Always plan first | Async tasks (AI is alone) |

**Decision: Soft default, hard for async.**

In sync, you can catch mistakes. In async, a bad plan wastes time and creates mess.

## How It Maps

### Sync (Chat Session)

```
User: "refactor auth system"
  → AI enters plan mode (self-triggered)
  → Writes plan
  → User approves
  → AI executes
```

Plan mode is already built in. Nothing to build.

### Async (Vault Task)

```
New note → AI writes:
  ## Idea (what you said)
  ## Approach (what I'll do)    ← plan/contract
  status: waiting                ← approval gate

Human reviews → submit: true

AI executes → updates Progress
```

The Approach section IS the plan. The `waiting` status IS the approval gate.

## Task.md with Planning

```markdown
---
status: new | working | waiting | done | dropped
submit: false
created: YYYY-MM-DD
---

## Idea
[Raw note from human]

## Approach
[AI's proposed plan — what to do, how, why]
[Written before heavy execution]
[Human approves by setting submit: true]

## Progress
(AI updates as work proceeds)

## Resources
(links to files/NNN-slug/)

---

## Feedback
(Human writes here)

## Lessons
(What was learned)
```

## Prompt Guidance

For async AI agents (in assessment.md):

> If the task is non-trivial or ambiguous:
> 1. Write the Approach section first
> 2. Set status: waiting
> 3. Wait for human approval
>
> If the task is clear and simple:
> 1. Just do it
> 2. Update Progress
> 3. Set status: done or waiting

## CLAUDE.md Addition

```markdown
## Planning

Heavy changes need a plan before execution.

- **Sync:** Use plan mode (built-in)
- **Async:** Write Approach section in task.md, set status: waiting
- **Skip for:** obvious fixes, small changes, clear instructions
```

## Amazon 6-Pager Parallel

| Amazon | This System |
|--------|-------------|
| 6-page memo | Approach section / plan file |
| Meeting review | Human reads task.md |
| Approval to proceed | submit: true |
| Execution | AI works, updates Progress |

The document forces clear thinking. Writing "what I'll do and why" catches bad ideas before they become bad code.

## Summary

- Don't build a planning system — plan mode exists for sync
- For async, the Approach section + waiting status = natural plan gate
- Bias toward planning in async, let AI judge in sync
- The plan is the contract: alignment before execution
