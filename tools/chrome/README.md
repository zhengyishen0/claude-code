# Chrome Tool

Browser automation with React/SPA support

## Usage

```bash
tools/chrome/run.sh <command> [args...] [+ command [args...]]...
```

## Commands

### snapshot
Capture page state as markdown (always saves full content)

```bash
snapshot [--diff]
```

**Behavior:**
- Always captures full page content
- Saves to `/tmp/chrome-snapshots/` with state-based naming
- Default: Show current page state
- `--diff`: Show changes vs previous snapshot (same URL + state)

**Examples:**
```bash
snapshot              # Capture and show current state
snapshot --diff       # Show changes since last snapshot
```

**State-Based Snapshots:**
Automatically detects page state for accurate comparisons:
- `base` - Normal page
- `dropdown` - Autocomplete/combobox expanded
- `overlay` - Date picker, filters, large popups
- `dialog` - Modal dialogs

Example filenames:
- `www.airbnb.com-base-1234567890.md`
- `www.airbnb.com-dropdown-1234567891.md`
- `www.airbnb.com-dialog-1234567892.md`

**Note:** `recon` is aliased to `snapshot` for backward compatibility

### open
Open URL (waits for load), then snapshot

```bash
open URL
```

### wait
Wait for DOM/element (10s timeout)

```bash
wait [selector] [--gone] [--network]
```

**Behavior:**
- No selector: Wait for `readyState=complete` + DOM stable (1.2s)
- With selector: Wait for CSS selector to appear
- `--gone`: Wait for element to disappear
- `--network`: Wait for network idle (no active requests)

**Examples:**
```bash
wait                          # readyState + DOM stable
wait --network                # Also wait for network idle
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

**Chain with wait/snapshot:**
```bash
click '...' + wait + snapshot --diff
click '...' + wait '[role=dialog]' + snapshot
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

**Chain with wait/snapshot:**
```bash
input '...' 'value' + wait + snapshot --diff
```

### esc
Send ESC key (close dialogs/modals)

```bash
esc
```

**Chain with +:**
```bash
esc + wait dialog --gone + snapshot
```

## Chaining Commands

Chain multiple commands with `+`:

```bash
# Typical workflow with diff tracking
input '#search' 'Paris' + wait + snapshot --diff
click '[data-testid="option-0"]' + wait + snapshot --diff
click '[data-testid="date-15"]' + wait + snapshot --diff

# Wait for network idle before snapshot
open "https://example.com" + wait --network + snapshot

# Complex chains
click "[@Close](#btn)" + wait "[role=dialog]" --gone + snapshot
```

## Key Principles

1. **URL params first** - Always prefer direct URLs over clicking
   ```bash
   open "https://airbnb.com/s/Paris?checkin=2025-12-20&checkout=2025-12-27"
   ```

2. **Use chrome tool commands** - Avoid `chrome-cli execute` unless truly needed

3. **Snapshot first** - Understand page before interacting
   ```bash
   open "https://example.com" + wait + snapshot
   ```

4. **Track changes with --diff** - See what changed after interactions
   ```bash
   click '[...]' + wait + snapshot --diff
   ```

5. **Chain with +** - Combine action + wait + snapshot in one call

6. **Wait for specific element** - Not just any DOM change
   ```bash
   click '[...]' + wait '[role=dialog]' + snapshot
   ```

7. **Use --gone** - When expecting element to disappear
   ```bash
   esc + wait '[role=dialog]' --gone + snapshot
   ```

8. **Use --network for lazy content** - Wait for footer/ads to load
   ```bash
   open "https://example.com" + wait --network + snapshot
   ```

## Typical Workflows

### Exploring a New Page
```bash
# First snapshot with network wait
open "https://example.com" + wait --network + snapshot

# Interact and track changes
input '#search' 'query' + wait + snapshot --diff
click '[data-testid="btn"]' + wait + snapshot --diff
```

### Form Filling
```bash
# Each step shows only what changed
open "https://form.com" + wait + snapshot
input '#name' 'John' + wait + snapshot --diff
input '#email' 'john@example.com' + wait + snapshot --diff
click '#submit' + wait + snapshot --diff
```

### Modal Interactions
```bash
# Open modal
click '[data-testid="open-modal"]' + wait '[role=dialog]' + snapshot

# Interact within modal (compares dialog state to dialog state)
input '#modal-input' 'value' + wait + snapshot --diff

# Close and verify
esc + wait '[role=dialog]' --gone + snapshot --diff
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
