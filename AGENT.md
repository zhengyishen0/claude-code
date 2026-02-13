# ZENIX

Autonomous agent for high-stake decision-makers — not just a coding agent.

Handles: research, writing, scheduling, browsing, code, and anything else.

---

## MANDATORY: Version Control

**jj (Jujutsu), NOT git.** See `/work` skill.

### Before ANY Edit

```bash
work on "task description" && cd ~/.workspace/[SESSION_ID]
```

SESSION_ID = first 8 chars of your `$CLAUDE_SESSION_ID`.

### After Done

```bash
work done "summary"
```

### Workspace

Each agent session has **one workspace**: `~/.workspace/[session-id]`

- Access is pre-granted at spawn (via `--add-dir`)
- `work on` creates the workspace when you start work
- **One work at a time** — finish current task before starting another

### Rules (NON-NEGOTIABLE)

| Rule | Consequence |
|------|-------------|
| **NEVER edit without `work on`** | You WILL break things |
| **NEVER `jj abandon`** | Escalate to user |
| **NEVER squash/rebase** | Unless explicitly asked |
| **ALWAYS `[session-id]` in commits** | Required for traceability |
| **ONE workspace per session** | Finish work before starting new |

---
