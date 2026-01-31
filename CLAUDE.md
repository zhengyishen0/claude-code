# Claude Code

Agent orchestration framework with browser automation, knowledge persistence, and supervision.

## Quick Decision Guide

| Need to... | Use |
|------------|-----|
| Make any code changes | `worktree create` first (main is protected) |
| Automate a website / fill forms / click buttons | `browser` |
| See what's on screen (any app) | `screenshot` |
| Recall how something was done before | `memory search` |
| Call external APIs (Google, etc.) | `api` (service) |
| Run background agents on tasks | `world spawn` + `supervisor` |
| Manage long-running processes | `daemon` |

## Workflow

**Always use worktrees** — main branch is protected to prevent accidents.

```bash
worktree create feature-name     # Before ANY file changes
# ... work using absolute paths to worktree ...
worktree merge feature-name      # When done: merge, archive, cleanup
worktree abandon feature-name    # If you want to discard instead
```

Keep clean: temp files in `tmp/`, stage changes promptly, commit at checkpoints.

## Tools

Run any tool without arguments for help.

---

### browser — Web automation

**When:** Interacting with websites — login, form filling, clicking, scraping, testing.

**Why browser vs screenshot:** Browser *controls* the page (clicks, inputs). Screenshot only *sees* native apps.

**Key insight:** URL params are 10x faster than form filling. Check `browser inspect` first.

```bash
browser open <url>              # Navigate and discover page structure
browser click <selector|x,y>    # Click by CSS selector or coordinates
browser input <selector> <val>  # Fill input (React-aware, triggers state)
browser snapshot [--full]       # See page state + diff from last snapshot
browser screenshot              # Capture for vision analysis
browser sendkey <key>           # esc, enter, tab, arrows
browser inspect                 # Discover URL params and form fields
```

Options: `--account SERVICE[:USER]` (inject Chrome cookies), `--debug` (headed mode)

---

### screenshot — Native app capture

**When:** Need to see what's on screen in *any* macOS app (not just browser).

**Why screenshot vs browser screenshot:** This captures *any window* (Finder, Slack, VSCode). Browser screenshot only captures the automated browser.

```bash
screenshot                    # List available windows
screenshot <app-name>         # Capture by app (fuzzy match)
screenshot <window-id>        # Capture specific window
```

---

### memory — Past session knowledge

**When:** Stuck on a problem, or need to recall how something was done before.

**Why:** Your past sessions contain solutions. Search before reinventing.

```bash
memory search "error handling api"           # Find relevant sessions
memory search "oauth" --recall "how did we handle refresh tokens?"
memory recall <session-id> "summarize the approach"
```

---

### api (service) — External APIs

**When:** Need to interact with Google (Gmail, Calendar, Drive), or other services.

**Why api vs browser:** Direct API calls are faster, more reliable, and don't require UI navigation.

```bash
api google admin                              # First-time setup
api google auth                               # Login
api google gmail users.messages.list userId=me
api google calendar events.list calendarId=primary
api google drive files.list q="name contains 'report'"
```

---

### world + supervisor — Background agents

**When:** Running multiple tasks in parallel, or tasks that take a long time.

**Why:** Spawn agents in isolated worktrees, track progress, verify results.

```bash
# Create and spawn a background task
task create "Refactor auth module"
world spawn <task-id>           # Starts agent in its own worktree

# Monitor
world                           # Recent events
world ps                        # Running agents

# Quality control
supervisor verify <task-id>     # Mark verified after review
supervisor cancel <task-id>     # Stop a task
supervisor retry <task-id>      # Retry failed task
```

---

### worktree — Git isolation

**When:** Always, before making any code changes.

**Why:** Protects main branch. Each feature gets isolated workspace. Easy to abandon failed experiments.

```bash
worktree                        # List all worktrees
worktree create <name>          # Create branch + worktree
worktree merge <name>           # Merge to main, archive, delete branch
worktree abandon <name>         # Archive without merging
```

---

### daemon — Background services

**When:** Need persistent processes (watchers, pollers) that survive terminal close.

```bash
daemon list                     # Available daemons
daemon <name> install           # Install and start
daemon <name> status            # Check if running
daemon <name> log               # View logs
```

---

### proxy — Network proxy

**When:** Behind a firewall or need to route traffic through proxy.

```bash
proxy status                    # Current proxy state
proxy check                     # Test connectivity
```

---

### task — Work items

**When:** Tracking multi-step work, especially with `world spawn`.

```bash
task create "title"             # Create task
task list                       # See all tasks
task show <id>                  # Details
```

## Setup

```bash
./setup              # Show status
./setup all          # Install everything
./setup shell        # Add to ~/.zshrc
```

## Architecture

- **world.log** — Append-only event log (source of truth)
- **task/data/** — Task state as markdown + YAML frontmatter
- **~/.worktrees/** — Isolated feature worktrees
- **~/.claude/memory-index.tsv** — Session search index
