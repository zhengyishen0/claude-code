# Intention Stage Prompt

You are processing a raw note that may contain multiple ideas. Your job is to organize them into logical tasks.

## Step 0: Analyze and group ideas

Read the note and identify distinct ideas. Then group them:

**Group related ideas into ONE task:**
- Same topic/domain
- Would be researched together
- Natural to compare/contrast

**Split unrelated ideas into SEPARATE tasks:**
- Different topics
- Independent work
- Different timelines/priorities

**Examples:**

```
研究Cursor和Aider的工作流
看看有没有其他AI coding工具
```
→ 1 task: "AI coding tools research" (all related)

```
研究tailscale
学一下日语
整理workflow文档
```
→ 3 tasks: networking, language learning, documentation (unrelated)

```
买机票去东京
订酒店
规划行程
```
→ 1 task: "Tokyo trip planning" (all related)

## Step 1: Check internal sources

Before writing:
- `/memory` — previous sessions
- Lessons — relevant patterns
- Related .md files
- Feishu/WeChat if relevant

## Step 2: Create task folder(s)

For each logical task group, create: `vault/Tasks/NNN-slug/`

Use consecutive numbers starting from the provided next number.

## Step 3: Create task.md (for each)

```markdown
---
type: task
status: intention
workdir:
created: YYYY-MM-DD
session_id:
---

## Idea

[This task's grouped ideas — from original note]

## Intentions

- [[intention.1]]

## Assessments

## Contracts

## Reports
```

## Step 4: Create intention.1.md (for each)

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

[What this task group is about, one sentence]

## Key Questions

(only if genuinely unclear)

## Human Feedback

---

## What

[The grouped requests]

## Why

[Motivation]

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

- **Group intelligently** — related items together, unrelated items separate
- **Fill templates EXACTLY**
- **Oneliner** — one sentence max
- **status: confirmed** — if understanding is clear
- **submit: false** — always
- Update `vault/index.md` with ALL new tasks

## Output

Report:
1. How many tasks created
2. What's in each task
3. Why grouped this way (if merged or split)
