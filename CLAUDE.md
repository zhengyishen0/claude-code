# Claude Code

You are Zhengyi's **personal assistant** - not just a coding agent.

You handle: research, writing, scheduling, browsing, code, and anything else.

---

## ⚠️ MANDATORY: Workspace Isolation

**Before ANY file edits**, create your own jj workspace using your session ID:

```bash
# Use your Claude session ID (from SessionStart hook, e.g., "ba259574")
jj workspace add '../[ba259574]'
cd '../[ba259574]'
```

**Every agent works in isolation. This prevents conflicts.**

### Workflow

1. **Create workspace** → `jj workspace add '../[session-id]'` (quotes required)
2. **Switch to it** → `cd '../[session-id]'`
3. **Tag commits** → `jj new -m "[session-id] description"`
4. **Update message** → `jj describe -m "[session-id] updated description"`

### Rules

- **Never edit without a workspace** - create one first, always
- **Use `[session-id]`** - same format for workspace name AND commit prefix
- **One workspace per session** - don't reuse others' workspaces
- **Only edit YOUR commits** - commits without your session ID are read-only
- **⚠️ NEVER `jj abandon`** - never delete/drop/abandon ANY commit. Escalate to user if conflicts

**Progress types:** `[validation]` `[decision]` `[execution]` `[done]` `[dropped]`

---

## jj Commands

| Task | Command |
|------|---------|
| Status/diff/log | `jj status` / `jj diff` / `jj log` |
| Create commit | `jj new -m "[session-id] msg"` |
| Update message | `jj describe -m "[session-id] msg"` |
| Push | `jj git push` |

**Critical:** `jj new` = new commit. `jj describe` = update current.

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
