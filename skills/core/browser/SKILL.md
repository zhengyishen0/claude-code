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

## Commands

### Primary

| Command | Usage |
|---------|-------|
| `open URL` | Navigate + inspect URL params + snapshot |
| `click SELECTOR` | Click element (auto-waits, auto-snapshots) |
| `input SELECTOR VALUE` | Fill input (React-compatible) |
| `hover X Y` | Hover at coordinates |
| `drag X1 Y1 X2 Y2` | Drag between coordinates |

### Utility

| Command | Usage |
|---------|-------|
| `snapshot [--full]` | Page content as markdown (smart diff) |
| `inspect` | Discover URL parameters from links/forms |
| `wait [SELECTOR]` | Wait for DOM stability or element |
| `sendkey KEY` | Keyboard input (esc, enter, tab, arrows) |
| `execute JS` | Run JavaScript code |
| `tabs` | List/switch/close browser tabs |
| `screenshot` | Visual capture for coordinate-based interaction |
| `profile` | List available accounts |

## Authentication

```bash
browser profile                              # List available accounts
browser --account github open "https://..."  # Cookie injection (Chromium)
browser --keyless open "https://..."         # Profile copy (Chrome Canary)
browser --debug open "https://..."           # Headed browser for debugging
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

## Command Details

### click

```bash
click SELECTOR [--index N]     # Click by selector
click X Y                       # Click at coordinates
```

Auto-feedback: clicks, waits for reaction, shows snapshot diff.

### input

```bash
input SELECTOR VALUE [--index N]
```

React-compatible: uses native property setters, triggers proper state updates.

### snapshot

```bash
snapshot [--full]
```

- Default: Smart diff (additions/deletions vs previous)
- `--full`: Force full snapshot output
- Auto-detects state: base, dropdown, overlay, dialog

### sendkey

Supported keys: `esc`, `enter`, `tab`, `space`, `backspace`, `delete`, arrows (`up`, `down`, `left`, `right`), `pageup`, `pagedown`, `home`, `end`, `f1-f12`

### screenshot

```bash
screenshot [--width=N] [--height=N] [--quality=N] [--full] [--png]
```

Default: 1200x800, JPEG quality 70. Token cost: `(width x height) / 750`

## When to Use

- Login/authentication flows (interact required)
- Form submissions (POST forms, checkout)
- Clicking through wizards
- Extracting page content
- Visual verification with screenshots

**Don't use for:** Search/filter forms (use URL params instead)

## Typical Workflows

### Search (URL Construction)

```bash
browser open "https://example.com"     # inspect shows URL params
browser open "https://example.com/search?q=laptop&price_max=1000"
```

### Login

```bash
browser open "https://example.com/login"
browser input "#email" "user@example.com"
browser input "#password" "password"
browser click "[Login]"
```

### Modal Interaction

```bash
browser click '[data-testid="open-modal"]'  # Opens modal
browser input "#modal-input" "value"         # Fill modal form
browser sendkey esc                          # Close modal
```
