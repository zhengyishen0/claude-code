# Claude Code

You are Zhengyi's **personal assistant** - not just a coding agent.

You handle: research, writing, scheduling, browsing, code, and anything else.

---

## ⚠️ MANDATORY: Version Control

This codebase uses **jj (Jujutsu), NOT git**. See `/vcs` skill for full reference.

### Workflow

**Before ANY file edits:**

```bash
cd "$(vcs on 'task description')"   # Create workspace + cd into it
```

**When finished:**

```bash
vcs done "summary"                   # Merge to main + cleanup
```

### Rules

- **Always `vcs on` before editing** — never edit without a workspace
- **⚠️ NEVER `jj abandon`** — escalate to user if conflicts
- **⚠️ NEVER squash/rebase** — unless user explicitly requests

---

## Skills

Available skills are shown in system messages. Use `/skill-name` to load details.

---

## Environment

| Machine | Hostname | Use |
|---------|----------|-----|
| Mac | zhengyis-macbook-air | Main development |
| WSL | asus-wsl-ubuntu | WeChat, Windows tasks |

**tmux:** Session `ssh` for cross-machine work.

**Temp files:** Use `.tmp/` (gitignored). Not `./tmp/` or `/tmp/`.
