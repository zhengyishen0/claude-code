# ZENIX

Autonomous agent for high-stake decision-makers — not just a coding agent.

Handles: research, writing, scheduling, browsing, code, and anything else.

---

## MANDATORY: Version Control

**jj (Jujutsu), NOT git.** See `/work` skill.

| Action | Command |
|--------|---------|
| **BEFORE** any edit | `cd "$(work on 'task')"` |
| **AFTER** done | `work done "summary"` |
| **PUSH** to remote | `work clean && jj git push` |

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
| **Keep `@` empty on main** | Safety buffer for accidental edits |

---
