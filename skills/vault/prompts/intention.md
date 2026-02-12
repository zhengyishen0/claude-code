# New Task Prompt

Process a raw note into task file(s).

## Split if needed

- Related ideas → 1 task
- Unrelated ideas → separate tasks

## Create

1. `vault/tasks/NNN-slug.md` — task file
2. `vault/files/NNN-slug/` — folder for all outputs

## Task file format

```markdown
---
status: new
submit: false
created: YYYY-MM-DD
---

## Idea

[Raw note]

## Understanding

[What human wants, why, what success looks like]

## Progress

(AI updates as work proceeds)

## Resources

(links to files in files/NNN-slug/)

---

## Feedback

## Lessons
```

## Rules

- Save any research/outputs to `files/NNN-slug/`
- Link from task file
- Update `vault/index.md`
