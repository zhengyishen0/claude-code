---
name: chrome-cli
description: Control Google Chrome browser via chrome-cli. Use for web automation, page interaction, form filling, data extraction, and browser testing. Invoke when user asks to interact with websites, click buttons, fill forms, scrape data, or automate browser tasks.
---

# Chrome Browser Control Skill

Control Google Chrome from the command line using `chrome-cli` for browser automation, web scraping, and interaction tasks.

## Prerequisites

- macOS with Google Chrome installed
- chrome-cli installed: `brew install chrome-cli`

## Core Commands

```bash
# Tab management
chrome-cli list tabs              # List all open tabs
chrome-cli info                   # Current tab info
chrome-cli open "URL"             # Open URL in new tab
chrome-cli activate -t TAB_ID     # Switch to specific tab

# JavaScript execution
chrome-cli execute "JS_CODE"      # Run JS in active tab
chrome-cli execute -t TAB_ID "JS" # Run JS in specific tab

# Page content
chrome-cli source                 # Get page HTML source
```

## Reconnaissance-First Workflow

**Always run recon before interacting with a page** to understand its structure:

```bash
# 1. Run the recon script to understand page layout
chrome-cli execute "$(cat html2md.js)"  # Run from skill directory

# 2. Based on recon output, write targeted JS queries
chrome-cli execute "document.querySelector('button[aria-label=\"Submit\"]').click(); 'clicked'"

# 3. Re-run recon to verify state changes
```

## Critical Rules

### 1. Always Return Strings from JS

chrome-cli crashes if JS returns `undefined` or `null`. Always wrap results:

```javascript
// BAD - may crash
chrome-cli execute "document.querySelector('button').click()"

// GOOD - returns string
chrome-cli execute "document.querySelector('button').click(); 'clicked'"
chrome-cli execute "document.querySelectorAll('a').length.toString()"
chrome-cli execute "'found: ' + (element ? element.innerText : 'none')"
```

### 2. Use Tab IDs to Avoid Confusion

The active tab can change unexpectedly. Always track and specify tab IDs:

```bash
# Get current tab ID
TAB_INFO=$(chrome-cli info)
TAB_ID=$(echo "$TAB_INFO" | grep "^Id:" | awk '{print $2}')

# Use explicit tab ID
chrome-cli execute -t $TAB_ID "document.title"
chrome-cli activate -t $TAB_ID
```

### 3. Prefer URL Parameters Over UI Clicks

Building URLs with parameters is faster and more reliable than clicking through UI:

```bash
# SLOW: Click location, type, click date picker, select dates, click guests...
# FAST: Build URL with all parameters
URL="https://airbnb.com/s/Location/homes?adults=5&checkin=2025-12-01&checkout=2025-12-30&price_min=5000&price_max=8000"
chrome-cli open "$URL"
```

### 4. Wait After Actions

Use `sleep` after clicks/navigation to let page update:

```bash
chrome-cli execute "document.querySelector('button').click(); 'clicked'"
sleep 1.5  # Wait for UI to update
chrome-cli execute "$(cat ~/.claude/skills/chrome-cli/html2md.js)"  # Recon again
```

## Common Patterns

### Finding and Clicking Elements

```javascript
// By text content
chrome-cli execute "
var btns = document.querySelectorAll('button');
var target = [...btns].find(b => b.innerText.includes('Submit'));
target ? (target.click(), 'clicked') : 'not found';
"

// By aria-label
chrome-cli execute "
var btn = document.querySelector('button[aria-label=\"Add to cart\"]');
btn ? (btn.click(), 'clicked') : 'not found';
"

// By index
chrome-cli execute "
var items = document.querySelectorAll('[role=\"option\"]');
items[0].click(); 'clicked first option';
"
```

### Form Input

```javascript
// Text input
chrome-cli execute "
var input = document.querySelector('input[name=\"email\"]');
input.value = 'test@example.com';
input.dispatchEvent(new Event('input', { bubbles: true }));
'set email';
"

// Select dropdown
chrome-cli execute "
var select = document.querySelector('select[name=\"country\"]');
select.value = 'US';
select.dispatchEvent(new Event('change', { bubbles: true }));
'selected US';
"
```

### Extracting Data

```javascript
// Get all links
chrome-cli execute "
var links = document.querySelectorAll('a[href]');
[...links].slice(0, 10).map(a => a.href).join('\\n');
"

// Get table data
chrome-cli execute "
var rows = document.querySelectorAll('table tr');
[...rows].map(r => [...r.cells].map(c => c.innerText).join(' | ')).join('\\n');
"

// Get structured data
chrome-cli execute "
var items = document.querySelectorAll('[data-testid=\"product-card\"]');
JSON.stringify([...items].map(i => ({
  title: i.querySelector('h2')?.innerText,
  price: i.querySelector('[data-price]')?.innerText
})));
"
```

### Handling Dialogs/Modals

```javascript
// Check if dialog is open
chrome-cli execute "
var dialog = document.querySelector('[role=\"dialog\"], dialog[open]');
dialog ? 'dialog open: ' + (dialog.getAttribute('aria-label') || 'unnamed') : 'no dialog';
"

// Close dialog
chrome-cli execute "
var closeBtn = document.querySelector('[role=\"dialog\"] button[aria-label*=\"close\"], [role=\"dialog\"] button[aria-label*=\"Close\"]');
closeBtn ? (closeBtn.click(), 'closed') : 'no close button';
"
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| JS returns nothing | Ensure you return a string: `'result'` not just expression |
| Wrong tab executing | Use `-t TAB_ID` explicitly |
| Element not found | Run recon first, check selectors, add `sleep` for dynamic content |
| Click doesn't work | Try `.dispatchEvent(new MouseEvent('click', {bubbles: true}))` |
| Input not updating | Dispatch `input` and `change` events after setting `.value` |
| Auth walls | Check for login state before actions requiring authentication |

## Files in This Skill

- [html2md.js](html2md.js) - Page reconnaissance script that outputs page structure in markdown format

## Example Workflow: Airbnb Search

```bash
# 1. Open with all filters in URL (fast approach)
URL="https://airbnb.com/s/Los-Angeles/homes?adults=4&checkin=2025-12-01&checkout=2025-12-07&price_min=200&price_max=500&room_types[]=Entire%20home/apt"
chrome-cli open "$URL"
sleep 4

# 2. Recon the page
chrome-cli execute "$(cat ~/.claude/skills/chrome-cli/html2md.js)"

# 3. Extract listing info
chrome-cli execute "
var prices = document.querySelectorAll('button[aria-label*=\"price\"]');
[...prices].slice(0, 5).map(p => p.getAttribute('aria-label')).join('\\n');
"

# 4. Click first wishlist button
chrome-cli execute "
var btn = document.querySelector('button[aria-label*=\"wishlist\"]');
btn ? (btn.click(), 'clicked: ' + btn.getAttribute('aria-label')) : 'not found';
"
```
