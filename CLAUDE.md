# Claude Code

Agent orchestration framework with browser automation, knowledge persistence, and supervision.

## Workflow

Main branch is protected. Use worktrees for all changes:

```bash
worktree create feature-name     # Create branch + worktree
# ... make changes using absolute paths ...
worktree merge feature-name      # Merge to main, archive, delete branch
```

Keep the tree clean:
- Temp files in `tmp/` (gitignored)
- Stage promptly, revert unwanted changes
- Commit at logical checkpoints

## Tools

Run any tool without arguments for help.

### worktree — Git worktree management
```bash
worktree                    # List worktrees with status
worktree create <name>      # Create worktree and branch
worktree merge <name>       # Merge to main and archive
worktree abandon <name>     # Archive without merging
```

### browser — Web automation with React/SPA support
```bash
browser open <url>              # Navigate and discover page
browser click <selector|x,y>    # Click element or coordinates
browser input <selector> <val>  # Set input (React-aware)
browser snapshot [--full]       # Capture page state with diff
browser screenshot              # Vision-based capture
browser sendkey <key>           # Keyboard input (esc, enter, tab)
browser tabs                    # Manage tabs
```
Options: `--account SERVICE[:USER]` (Chrome cookies), `--keyless` (profile copy), `--debug` (headed)

### memory — Cross-session knowledge search
```bash
memory search "keywords"                    # Search all sessions (OR-based)
memory search "keywords" --recall "question"  # Search then ask deeper
memory recall <session-id> "question"       # Query specific session
```

### world — Agent coordination and event log
```bash
world                   # Show recent events
world ps                # List running task agents
world record <type> <msg>  # Record event
world spawn <task-id>   # Start agent in worktree
world watch             # Run polling daemon
```

### supervisor — L2 quality assurance
```bash
supervisor verify <task-id>   # Mark task verified
supervisor cancel <task-id>   # Cancel execution
supervisor retry <task-id>    # Retry from archive
```

### service (api) — Universal API interface
```bash
api <service> admin     # One-time credential setup
api <service> auth      # User authentication
api <service> status    # Check auth state
# Google examples:
api google gmail users.messages.list userId=me
api google calendar events.list calendarId=primary
api google drive files.list q="name contains 'report'"
```

### screenshot — macOS window capture for vision
```bash
screenshot              # List available windows
screenshot <app-name>   # Capture by app (fuzzy match)
screenshot <window-id>  # Capture by ID
```

### proxy — Proxy management
```bash
proxy status    # Show proxy status
proxy check     # Test reachability
proxy config    # Manage config file
```

## Supporting Tools

### task — Work item management
```bash
task create <title>     # Create task
task list               # List all tasks
task show <id>          # Show details
```

### daemon — macOS LaunchAgent manager
```bash
daemon list                 # List available daemons
daemon <name> install       # Install and start
daemon <name> status        # Check status
daemon <name> log           # Tail log
```

## Setup

```bash
./setup          # Show installation status
./setup all      # Install everything
./setup shell    # Add to ~/.zshrc
```

## Architecture

- **world.log** — Append-only event log (source of truth)
- **task/data/** — Per-task markdown with YAML frontmatter
- **~/.worktrees/** — Isolated feature worktrees
- **~/.claude/memory-index.tsv** — Session search index
