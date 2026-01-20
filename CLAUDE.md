# Claude Code

Personal tools for AI-assisted development workflows.

## Constraints

- **Main branch protected** - PreToolUse hook blocks Edit/Write/commit on main
- **Use worktrees** - `worktree create <name>` before any changes
- **No args = help** - All tools show help when run without arguments
- **Stage after edit** - `git add <file>` immediately after each change

## Project Structure

```
paths.sh              # Central path config (source this)
shell-init.sh         # Shell entry point (sourced by ~/.zshrc)
docs/                 # Documentation
tools/                # screenshot, proxy, api
browser/              # Browser automation
memory/               # Cross-session knowledge search
world/                # Event log and task coordination
worktree/             # Worktree management
supervisor/           # Multi-agent task orchestration
```

## Tools

| Tool | Purpose | Key Commands |
|------|---------|--------------|
| `world` | Event log, task coordination | `create`, `check`, `watch`, `spawn` |
| `supervisor` | Multi-agent orchestration | `run`, `retry`, `status` |
| `worktree` | Git worktree management | `create`, `cleanup` |
| `memory` | Cross-session search | `search`, `recall` |
| `browser` | Browser automation | `snapshot`, `click`, `input`, `execute` |
| `api` | HTTP API client | `get`, `post`, `put`, `delete` |
| `screenshot` | Window capture | `<app_name>`, `--list` |
| `proxy` | VPN-aware proxy | `check`, `enable`, `disable` |

Run any tool without args for full help.

## Paths

All scripts source `paths.sh` for consistent path resolution:

```bash
source "$SCRIPT_DIR/../paths.sh"  # Relative to script location
```

Key variables: `PROJECT_DIR`, `PROJECT_WORKTREES`, `PROJECT_ARCHIVE`, `TASKS_DIR`, `WORLD_LOG`

## Hooks

| Hook | Trigger | Action |
|------|---------|--------|
| PreToolUse | Edit/Write/Bash on main | Block with worktree reminder |
| PostToolUse | git commit | Log to world.log |
| SessionStart | compact | Show branch warning if on main |

## Worktree Workflow

```bash
worktree create feature-name     # Create and switch
# ... make changes using absolute paths ...
worktree cleanup feature-name    # Merge, remove, delete branch
```

Use absolute paths: `$PROJECT_WORKTREES/feature-name/src/file.js`

## Browser Automation Priority

1. **URL params** - Construct URLs for navigation (fastest)
2. **Selectors** - CSS selectors or text matching
3. **Vision** - Screenshot + coordinates (last resort)
