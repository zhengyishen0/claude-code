# Claude Code

Toolkit for browser automation, knowledge persistence, and API access.

## Where Does Information Live?

| Looking for... | Use | Examples |
|----------------|-----|----------|
| Past events, "what did I do", appointments | `api google calendar` | "last summer", "dentist", "meetings" |
| Emails, notifications, order status, replies | `api google gmail` | "shipping update", "job reply", "cord blood status" |
| Files in cloud storage | `api google drive` | "project folder", "shared docs" |
| Spreadsheet data | `api google sheets` | "Q4 budget", "expense report" |
| Facts from past coding sessions | `memory search` | "laptop spec", "API key", "port number" |
| How/why we did something (needs thinking) | `memory --recall` | "OAuth approach", "how we solved X", "progress on Y" |
| What's on screen right now (any app) | `screenshot` | "Figma design", "terminal output", "Slack message" |
| Interact with websites | `browser` | "buy VPS", "sign up", "book flight", "upload to TestFlight" |
| Change code | `worktree` first | "fix bug", "add feature", "refactor" |

## Quick Rules

1. **"What did I do..."** → Calendar (events), not memory
2. **"Updates on..." / "Status of..."** → Gmail (notifications come via email)
3. **"What was the [fact]"** → `memory search` (lookup)
4. **"How did we..." / "Progress on..."** → `memory --recall` (synthesis)
5. **Code changes** → `worktree create` first, always

## Workflow

Main branch is protected. Use worktrees:

```bash
worktree create feature-name     # Before ANY file changes
worktree merge feature-name      # When done
worktree abandon feature-name    # To discard
```

## Tools

### worktree — Git isolation
```bash
worktree create <name>          # Create branch + worktree
worktree merge <name>           # Merge to main, cleanup
worktree abandon <name>         # Discard without merging
```

### browser — Web automation
**When:** Websites — login, forms, clicking, purchasing, uploading.

```bash
browser open <url>              # Navigate
browser click <selector|x,y>    # Click
browser input <selector> <val>  # Fill input
browser snapshot                # See page state
```

### screenshot — Native app capture
**When:** See any macOS app window (Terminal, Figma, Slack, Finder).

```bash
screenshot <app-name>           # Capture by app name
```

### memory — Past session knowledge

**`memory search`** — Find specific facts (names, specs, numbers, configs)
```bash
memory search "asus laptop spec"
memory search "wechat database path"
```

**`memory --recall`** — Synthesize/analyze (how, why, progress, approach)
```bash
memory search "oauth" --recall "what approach did we use?"
memory search "wechat" --recall "how far did we get?"
```

### api — Google APIs
**When:** Personal data in Google (calendar, email, drive, sheets).

```bash
# Calendar - events, schedule, appointments, "what did I do"
api google calendar events.list calendarId=primary

# Gmail - emails, order updates, replies, notifications
api google gmail users.messages.list userId=me q="subject:shipping"

# Drive - cloud files
api google drive files.list q="name contains 'report'"

# Sheets - spreadsheet data
api google sheets spreadsheets.get spreadsheetId=<id>
```

## Setup

```bash
./setup all          # Install everything
./setup shell        # Add to ~/.zshrc
```
