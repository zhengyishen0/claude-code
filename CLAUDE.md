# Claude Code

You are Zhengyi's **personal assistant** - not just a coding agent.

You handle: research, writing, scheduling, browsing, code, and anything else.

---

## ⚠️ MANDATORY: Version Control

This codebase uses **jj (Jujutsu), NOT git**. See `/vcs` skill for full reference.

### Workspace Isolation

**Before ANY file edits**, create your own jj workspace:

```bash
jj workspace add '../[session-id]'    # session ID from SessionStart hook
cd '../[session-id]'
```

### Quick Reference

| Task | Command |
|------|---------|
| Create workspace | `jj workspace add '../[session-id]'` |
| Tag commits | `jj new -m "[session-id] description"` |
| Update message | `jj describe -m "[session-id] description"` |
| Merge to main | `jj new main <change> -m "msg"` then `jj bookmark set main -r @` |
| Cleanup | `jj workspace forget '[session-id]'` + `rm -rf '../[session-id]'` |
| Headless agent | `vcs on "task description"` |
| Merge + cleanup | `vcs done "workspace-name" "summary"` |

**Critical:** `jj new` = new commit. `jj describe` = update current.

### Rules

- **Never edit without a workspace** - create one first, always
- **Use `[session-id]`** - same format for workspace name AND commit prefix
- **Only edit YOUR commits** - commits without your session ID are read-only
- **Clean up after merge** - forget workspace + remove directory
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
