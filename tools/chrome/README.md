# Chrome Tool

Browser automation with React/SPA support

## Usage

```bash
tools/chrome/run.sh <command> [args...] [+ command [args...]]...
```

## Commands

### recon
Get page structure as markdown

```bash
recon [--full] [--status] [--diff]
```

By default, shows structure + interactive sections (Dialog, Form, Nav) with collapsed repetitive content.

**Options:**
- `--full`: Show all details (original verbose behavior)
- `--status`: Show loading info (images, scripts, etc.)
- `--diff`: Show changes since last recon

**Filter output with grep/awk:**
```bash
recon | awk '/^## Nav($|:)/,/^## [^N]/'   # Show Nav
recon | awk '/^## Main($|:)/,/^## [^M]/'  # Show Main
recon | awk '/^## Dialog/,/^## [^D]/'     # Show Dialog
```

### inspect
Discover URL parameters and form structures (Universal URL Discovery)

```bash
inspect [--json] [--detail]
```

Combines **Tier 1** (link extraction) + **Tier 2** (form inspection) to discover all URL parameters and forms on the current page.

**Default behavior:**
- Shows meaningful placeholders: `search_query=<query>&v=<video_id>`
- Self-documenting URL patterns

**Options:**
- `--json`: Output raw JSON for programmatic use
- `--detail`: Show generic placeholders: `search_query=<value>&v=<value>`

**Examples:**
```bash
# Discover URL structure
inspect
# Output: https://youtube.com/results?search_query=<query>&v=<video_id>

# Get JSON for parsing
inspect --json

# Show all params with generic placeholders
inspect --detail

# Chain with open
open "https://airbnb.com" + wait + inspect
```

**What it discovers:**
- Parameters from existing links (Tier 1)
- Form field names and types (Tier 2)
- Suggested URL pattern with examples
- All forms and their actions

**Smart placeholder conversion:**
- `v` → `<video_id>` (YouTube)
- `q`, `query`, `search` → `<query>`
- `checkin`, `checkout` → `<checkin>`, `<checkout>`
- `page`, `offset`, `limit` → `<page>`, `<offset>`, `<limit>`
- `token`, `auth` → `<token>`
- 20+ more patterns

**Use case:**
Build search URLs without manual clicking - inspect discovers the structure, you construct the URL.

### open
Open URL (waits for load), then recon

```bash
open URL [--status]
```

**Options:**
- `--status`: Show loading info after page loads

### wait
Wait for DOM/element (10s timeout)

```bash
wait [selector] [--gone]
```

**Behavior:**
- No selector: Wait for `readyState=complete` + DOM stable
- With selector: Wait for CSS selector to appear
- `--gone`: Wait for element to disappear

**Examples:**
```bash
wait                          # readyState + DOM stable
wait '[role=dialog]'          # wait for modal
wait '[data-testid="x"]'      # wait for element
wait '[role=dialog]' --gone   # wait for modal to close
```

### click
Click element by CSS selector

```bash
click SELECTOR
```

**Examples:**
```bash
click '[data-testid="search-button"]'
click '#submit-btn'
click '[aria-label="Search"]'
click 'button.primary'
```

**Chain with wait/recon:**
```bash
click '...' + wait + recon
click '...' + wait '[role=dialog]' + recon
```

### input
Set input value by CSS selector

```bash
input SELECTOR VALUE
```

**Examples:**
```bash
input '[aria-label="Where"]' 'Paris'
input '#email' 'test@example.com'
input '[name="search"]' 'query'
```

**Chain with wait/recon:**
```bash
input '...' 'value' + wait + recon
```

### esc
Send ESC key (close dialogs/modals)

```bash
esc
```

**Chain with +:**
```bash
esc + wait dialog --gone + recon
```

## Element Formats

Universal across recon/click/input:

**Actionable elements:**
```
[text@aria](#id|#testid|.selector|/path)
```

Examples:
- `[@Search](#btn)`
- `[Submit](#submit-btn)`
- `[Next](/path)`

Usage: `click "[@Search](#btn)"`

**Input fields:**
```
Input: aria="label" (type)
```

Examples:
- `Input: aria="Where" (search)`
- `Input: aria="Email" (email)`

Usage: `input "@Where=Paris"` or `input "@Email=test@example.com"`

**Tip:** Copy formats directly from recon output for best results

## Chaining Commands

Chain multiple commands with `+`:

```bash
click "[@Submit](#btn)" + wait + recon
click "[@Close](#btn)" + wait "[role=dialog]" --gone + recon
input "@Search=tokyo" + wait "[role=listbox]" + recon
```

## Key Principles

1. **URL params first** - Always prefer direct URLs over clicking
   ```bash
   open "https://airbnb.com/s/Paris?checkin=2025-12-20&checkout=2025-12-27"
   ```

2. **Use chrome tool commands** - Avoid `chrome-cli execute` unless truly needed

3. **Recon first** - Understand page before interacting

4. **Chain with +** - Combine action + wait + recon in one call

5. **Wait for specific element** - Not just any DOM change

6. **Use --gone** - When expecting element to disappear

7. **Filter recon with grep/awk** - Extract specific sections
   ```bash
   recon | awk '/^## Main($|:)/,/^## [^M]/'
   ```

## Raw chrome-cli Commands

For direct browser control:

```bash
chrome-cli list tabs              # List all tabs
chrome-cli info                   # Current tab info
chrome-cli close [-t ID]          # Close tab
chrome-cli open URL               # Open URL
chrome-cli activate -t ID         # Switch to tab
chrome-cli execute JS             # Execute JavaScript
```

## Prerequisites

- `chrome-cli` must be installed
- Google Chrome must be running
- Run without args to check prerequisites:
  ```bash
  tools/chrome/run.sh
  ```
