---
name: browser
description: Browser automation with React/SPA support. Use when user needs to interact with websites, fill forms, click buttons, or capture page content.
---

# Browser Tool

Headless browser automation via Chrome DevTools Protocol.

## Quick Start

```bash
browser open "https://example.com"     # Open URL, show page content
browser click "Button Text"            # Click element
browser input "#email" "user@test.com" # Fill input field
browser snapshot                       # Capture current page state
browser screenshot                     # Visual capture for AI analysis
```

## Key Commands

| Command | Usage |
|---------|-------|
| `open URL` | Navigate + inspect URL params + snapshot |
| `click SELECTOR` | Click element (auto-waits, auto-snapshots) |
| `input SELECTOR VALUE` | Fill input (React-compatible) |
| `snapshot` | Page content as markdown (smart diff) |
| `screenshot` | Visual capture for coordinate-based interaction |
| `sendkey KEY` | Keyboard input (esc, enter, tab, arrows) |
| `tabs` | List/switch/close browser tabs |

## Authentication

```bash
browser profile                              # List available accounts
browser --account github open "https://..."  # Use saved credentials
browser --keyless open "https://..."         # Use Chrome profile copy
```

## Key Principles

1. **URL params first** - Build direct URLs instead of filling forms (10x faster)
   ```bash
   # Good
   browser open "https://airbnb.com/s/Paris?checkin=2025-12-20"

   # Slow (avoid for search/filter)
   browser input "#location" "Paris"
   browser click "Search"
   ```

2. **Auto-feedback** - Commands automatically wait and show results

3. **Use sendkey for modals** - `sendkey esc` is more reliable than finding close buttons

## When to Use

- Login/authentication flows
- Form submissions (POST forms, checkout)
- Clicking through wizards
- Extracting page content
- Visual verification with screenshots
