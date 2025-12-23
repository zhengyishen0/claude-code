# Chrome Tool

Browser automation with React/SPA support

## Usage

```bash
claude-tools chrome <command> [args...] [+ command [args...]]...
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

### inspect
Discover URL parameters from links and forms on the current page

```bash
inspect
```

**Behavior:**
- Extracts URL parameters from all links on the page (Tier 1)
- Inspects form fields and their names (Tier 2)
- Generates URL pattern with meaningful placeholders
- Shows examples of parameter values found

**Output:**
- Summary of discovered parameters
- List of all parameters with examples
- Form details if any
- Suggested URL pattern for direct navigation

**Examples:**
```bash
# Chain with + for single invocation
open "https://www.airbnb.com" + wait + inspect

# Or run separately
open "https://www.airbnb.com"
inspect
```

**Use Case:**
Use inspect to understand a site's URL structure before automating. This helps you construct direct URLs with the right parameters instead of clicking through UI.

**Example Output:**
```
URL Parameter Discovery
============================================================

Summary:
  Parameters from links: 20
  Parameters from forms: 1
  Total forms found: 1

Discovered Parameters:
------------------------------------------------------------
  check_in             [links] '2025-12-15'
  check_out            [links] '2025-12-22'
  adults               [links] '5'
  query                [ form]

URL Pattern:
------------------------------------------------------------
  https://example.com?check_in=<check_in>&check_out=<check_out>&adults=<adults>&query=<query>
```

### open
Open URL, discover URL structure, show page content

```bash
open URL
```

**Auto-feedback behavior:**
1. Opens the URL
2. Waits for page to load
3. Runs `inspect` to show URL parameters/structure
4. Takes `snapshot` to show page content

**Why inspect is included:**
Understanding the URL structure helps build direct URLs instead of clicking through the UI (follows "URL params first" principle).

**Example output:**
```
URL Parameter Discovery
[URL parameters and forms discovered]

# Page Title
[Page snapshot]
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
Click element and show immediate feedback

```bash
click SELECTOR
```

**Auto-feedback behavior:**
1. Clicks the element
2. Waits for page to react (DOM stable)
3. Shows snapshot diff (or full snapshot if state changed)

**Why auto-feedback:**
- See results immediately (modal opened, page navigated, etc.)
- No need to manually chain `+ wait + snapshot`
- Catch failures instantly (nothing changed = likely error)

**Examples:**
```bash
click '[data-testid="search-button"]'   # Shows search results
click '#filter-btn'                     # Shows filter panel
click '[aria-label="Close"]'            # Shows modal closed

# Advanced: wait for specific element before snapshot
click '...' + wait '[role=dialog]' + snapshot
```

### input
Set input value and show immediate feedback

```bash
input SELECTOR VALUE
```

**Auto-feedback behavior:**
1. Sets the input value
2. Waits for page to react (autocomplete, validation, etc.)
3. Shows snapshot diff (or full snapshot if state changed)

**Why auto-feedback:**
- See autocomplete suggestions immediately
- Catch validation errors instantly
- Know if input triggered page changes

**Examples:**
```bash
input '#search' 'Tokyo'              # Shows autocomplete dropdown
input '#email' 'invalid'             # Shows validation error
input '[aria-label="Where"]' 'Paris' # Shows location suggestions

# Advanced: manual control if needed
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

Commands can still be chained with `+` for advanced control:

```bash
# Auto-feedback is built-in (no chaining needed)
click '[data-testid="btn"]'                    # Auto waits + snapshots
input '#search' 'Paris'                        # Auto waits + snapshots

# Manual chaining for advanced cases
esc + wait '[role=dialog]' --gone + snapshot   # Wait for specific condition
open "https://example.com" + wait --network    # Custom wait before snapshot
click '[btn]' + wait '[role=dialog]'           # Wait for specific element
```

**Note:** With auto-feedback, manual chaining is rarely needed. Use it only for:
- Waiting for specific elements/conditions
- Custom timing requirements
- Suppressing auto-snapshot (advanced)

## Key Principles

1. **URL params first** - Always prefer direct URLs over clicking
   ```bash
   open "https://airbnb.com/s/Paris?checkin=2025-12-20&checkout=2025-12-27"
   ```
   The `open` command shows URL structure via `inspect`, making it easy to build direct URLs.

2. **Auto-feedback shows results** - `click` and `input` automatically show feedback
   ```bash
   click '[data-testid="btn"]'   # Automatically waits and snapshots
   input '#search' 'query'        # Shows autocomplete automatically
   ```

3. **Trust the tool** - Commands wait for stability before showing results
   - No need to manually chain `+ wait + snapshot`
   - Automatic diff when page state stays the same
   - Fallback to full snapshot when state changes (modals, navigation)

4. **Use chrome tool commands** - Built-in commands handle most automation needs

5. **Manual chaining for advanced cases** - Override auto-behavior when needed
   ```bash
   click '[btn]' + wait '[role=dialog]'         # Wait for specific element
   esc + wait '[role=dialog]' --gone + snapshot # Custom wait condition
   ```

## Typical Workflows

### Exploring a New Page
```bash
# Open shows URL structure + page content automatically
open "https://example.com"

# Interactions provide immediate feedback
input '#search' 'query'        # Shows autocomplete
click '[data-testid="btn"]'    # Shows results
```

### Form Filling
```bash
# Each command shows feedback automatically
open "https://form.com"
input '#name' 'John'                      # Shows name filled
input '#email' 'john@example.com'         # Shows email filled + validation
click '#submit'                           # Shows success/error message
```

### Modal Interactions
```bash
# Open modal (shows modal content automatically)
click '[data-testid="open-modal"]'

# Interact within modal (auto-feedback shows changes)
input '#modal-input' 'value'

# Close modal (auto-feedback confirms it closed)
esc + wait '[role=dialog]' --gone + snapshot
```

