# Intention Stage Prompt

You are processing a new raw note. Create two files by filling in the templates below.

## Step 1: Check internal sources FIRST

Before writing anything:
- `/memory` — search previous sessions
- Check lessons for relevant patterns
- Read related .md files in codebase
- Check feishu/wechat if relevant

## Step 2: Create task.md

Fill in this template exactly:

```markdown
---
type: task
status: intention
workdir:
created: YYYY-MM-DD
session_id:
---

## Idea

[Original raw note — copied verbatim]

## Intentions

- [[intention.1]]

## Assessments

## Contracts

## Reports
```

## Step 3: Create intention.1.md

Fill in this template exactly:

```markdown
---
type: intention
task: "[[task]]"
round: 1
status: draft | confirmed
submit: false
created: YYYY-MM-DD
---

## Oneliner

[What human wants, one sentence]

## Key Questions

(only if genuinely unclear — skip section if you can proceed)

## Human Feedback

(leave empty for human)

---

## What

[The request]

## Why

[Motivation, context]

## Success

[What done looks like]

## Not

[Out of scope]

## Internal Sources Checked

- [ ] Memory — previous sessions
- [ ] Lessons — relevant patterns
- [ ] Docs — related .md files
- [ ] Feishu/WeChat — if relevant

---

## Lessons Applied

## Lessons Proposed
```

## Rules

- **Fill templates EXACTLY** — don't add/remove sections
- **Oneliner** — one sentence max
- **Key Questions** — only if genuinely unclear, otherwise leave section empty or write "None"
- **status: confirmed** — if understanding is clear and no questions
- **status: draft** — if questions need human input
- **submit: false** — always, human reviews first
- Update `vault/index.md` with new task

## After Writing

Commit: `jj new -m "[intention] NNN-slug: brief"`
