---
name: chrome-cli
description: Control Google Chrome browser via chrome-cli. Use for web automation, page interaction, form filling, data extraction, and browser testing. Invoke when user asks to interact with websites, click buttons, fill forms, scrape data, or automate browser tasks.
---

# Chrome Browser Control Skill

Control Google Chrome from the command line using `chrome-cli` for browser automation, web scraping, and interaction tasks.

## Prerequisites

- macOS with Google Chrome installed
- chrome-cli installed: `brew install chrome-cli`

## chrome-cli-plus (Recommended)

Enhanced wrapper with React/SPA support:

```bash
skills/chrome-cli/chrome-cli-plus.sh <command> [args...]
```

| Command | Usage | Description |
|---------|-------|-------------|
| `recon` | `chrome-cli-plus.sh recon [--status]` | Wait 1s, get page structure (--status shows load info) |
| `open` | `chrome-cli-plus.sh open "URL" [--status]` | Open URL and recon (--status shows load info) |
| `wait` | `chrome-cli-plus.sh wait [timeout] [selector] [--gone]` | Wait for DOM change or element |
| `click` | `chrome-cli-plus.sh click "SELECTOR"` | Click element (React-compatible) |
| `input` | `chrome-cli-plus.sh input "SELECTOR" "VALUE"` | Set input value (React-compatible) |
| `tabs` | `chrome-cli-plus.sh tabs` | List all tabs |
| `info` | `chrome-cli-plus.sh info` | Current tab info |
| `close` | `chrome-cli-plus.sh close [TAB_ID]` | Close tab |

### Examples

```bash
# Open a page and get its structure
skills/chrome-cli/chrome-cli-plus.sh open "https://example.com"

# Click a button
skills/chrome-cli/chrome-cli-plus.sh click "button.submit"

# Fill a form field
skills/chrome-cli/chrome-cli-plus.sh input "#email" "test@example.com"

# Wait for any DOM change (after action)
skills/chrome-cli/chrome-cli-plus.sh wait 5

# Wait for specific element to appear
skills/chrome-cli/chrome-cli-plus.sh wait 10 ".results-loaded"

# Wait for loading spinner to disappear
skills/chrome-cli/chrome-cli-plus.sh wait 10 ".spinner" --gone

# Chain commands with wait
skills/chrome-cli/chrome-cli-plus.sh click "#submit" && skills/chrome-cli/chrome-cli-plus.sh wait 5 ".success"
```

## Key Principles

1. **Recon first** - Always run `recon` before interacting to understand page structure
2. **Always return strings** - JS must return a string or chrome-cli crashes (e.g., `element.click(); 'done'`)
3. **Use URL parameters** - Faster and more reliable than clicking through UI
4. **Wait after actions** - Use `wait` after clicks/navigation for page updates
5. **Re-run recon** - After any action, recon again to verify state changes
6. **Keep window clean** - Before opening a new tab, close unused tabs with `close TAB_ID`

## Raw chrome-cli Commands

For advanced use cases:

```bash
chrome-cli list tabs              # List all open tabs
chrome-cli info                   # Current tab info
chrome-cli open "URL"             # Open URL in new tab
chrome-cli activate -t TAB_ID     # Switch to specific tab
chrome-cli execute "JS_CODE"      # Run JS in active tab
chrome-cli source                 # Get page HTML source
```
