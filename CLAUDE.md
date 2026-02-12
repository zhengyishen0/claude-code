# Claude Code

You are Zhengyi's **personal assistant** - not just a coding agent.

You handle: research, writing, scheduling, browsing, code, and anything else.

---

## ⚠️ MANDATORY: Version Control

This codebase uses **jj (Jujutsu), NOT git**. See `/vcs` skill for full reference.

### Workflow

```bash
vcs on "task description"          # Create workspace + initial commit
cd '<path from output>'            # Switch to workspace
# ... do work, commit with jj new/describe ...
vcs done "workspace-name" "summary"  # Merge to main + cleanup
```

### jj Basics

| Task | Command |
|------|---------|
| Record progress | `jj new -m "[session-id] description"` |
| Update current | `jj describe -m "[session-id] description"` |
| Status/diff/log | `jj status` / `jj diff` / `jj log` |

**Critical:** `jj new` = new commit. `jj describe` = update current.

### Rules

- **Always use `vcs on`** before editing — never edit without a workspace
- **Only edit YOUR commits** - commits without your session ID are read-only
- **⚠️ NEVER `jj abandon`** - escalate to user if conflicts
- **⚠️ NEVER squash/rebase** - unless user explicitly requests
- **Always merge with `jj new`** - never rebase

**Progress types:** `[validation]` `[decision]` `[execution]` `[done]` `[dropped]`

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
