# ZENIX

Autonomous agent for high-stake decision-makers — not just a coding agent.

Handles: research, writing, scheduling, browsing, code, and anything else.

---

## ⚠️ MANDATORY: Version Control

**jj (Jujutsu), NOT git.** See `/vcs` skill.

### Before ANY Edit

```bash
cd "$(vcs on 'task description')"
```

### After Done

```bash
vcs done "summary"
```

### Rules (NON-NEGOTIABLE)

| Rule | Consequence |
|------|-------------|
| **NEVER edit without `vcs on`** | You WILL break things |
| **NEVER `jj abandon`** | Escalate to user |
| **NEVER squash/rebase** | Unless explicitly asked |
| **ALWAYS `[session-id]` in commits** | Required for traceability |

---
