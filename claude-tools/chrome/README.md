# Chrome Tool

Browser automation with React/SPA support

## Usage

```bash
claude-tools chrome <command> [args...]
```

## Commands

### snapshot
Capture page state as markdown with smart diff by default

```bash
snapshot [--full]
```

**Behavior:**
- Always saves full page content to `/tmp/chrome-snapshots/` with state-based naming
- Default: Show smart diff (additions/deletions vs previous snapshot)
- `--full`: Force full snapshot output (ignores diff)
- Auto-detects when full snapshot is needed (URL/title/modal change, or no previous snapshot)

**Examples:**
```bash
snapshot              # Smart diff (or full if first time / state changed)
snapshot --full       # Force full snapshot output
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
# Open automatically runs inspect
open "https://www.airbnb.com"

# Or run inspect separately if already on page
inspect
```

**Use Case:**
Use inspect to understand a site's URL structure before automating. This helps you construct direct URLs with the right parameters instead of clicking through UI.

**IMPORTANT:** Building URLs with parameters is 10x faster than form filling. Always prefer URL construction over `interact` commands for search/filter forms.

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
wait [selector]
```

**Behavior:**
- No selector: Wait for `readyState=complete` + DOM stable (1.2s)
- With selector: Wait for CSS selector to appear

**Examples:**
```bash
wait                          # readyState + DOM stable
wait '[role=dialog]'          # wait for modal
wait '[data-testid="x"]'      # wait for element
```

**Note:** Element disappearance is detected automatically via smart diff. No need to explicitly wait for elements to disappear.

### interact
Click or input on element (unified command)

```bash
interact SELECTOR [--input VALUE] [--index N]
```

**Auto-feedback behavior:**
1. Clicks element (or sets input if --input provided)
2. Waits for page to react with smart contextual wait
3. Shows snapshot diff automatically

**Options:**
- `--input VALUE`: Set input value instead of clicking
- `--index N`: Select Nth match when multiple elements found

**Why auto-feedback:**
- See results immediately (modal opened, autocomplete shown, etc.)
- Smart contextual wait tracks parent container changes
- Automatic snapshot shows what changed

**Examples:**
```bash
interact "Search"                         # Click by text, shows results
interact "#email" --input "user@ex.com"   # Fill input, shows validation
interact "[Submit]" --index 2             # Click 2nd submit button
```

**When to use interact:**
- Login forms (POST requests, session cookies)
- Checkout flows (multi-step wizards)
- Actions that can't be done via URL params

**When NOT to use interact:**
- Search/filter forms → Use URL construction instead (10x faster)
- Navigation → Use `open` with direct URLs


### sendkey
Send keyboard input (auto-runs wait and snapshot)

```bash
sendkey <key>
```

**Supported keys:**
- **Common:** esc, enter, tab, space, backspace, delete
- **Arrows:** arrowup, arrowdown, arrowleft, arrowright (or: up, down, left, right)
- **Navigation:** pageup, pagedown, home, end
- **Function:** f1-f12

**Auto-feedback behavior:**
1. Sends the keyboard event
2. Waits for page to react
3. Shows snapshot diff automatically

**Why sendkey instead of clicking:**
- More reliable for closing modals (ESC is a standard shortcut)
- Works even when buttons are hidden or dynamically positioned
- Handles keyboard-only interactions (accessibility, shortcuts)

**Examples:**
```bash
sendkey esc              # Close modal, shows snapshot
sendkey enter            # Submit form, shows result
sendkey arrowdown        # Navigate dropdown, shows selection
sendkey tab              # Move focus, shows change
```

**When to use sendkey:**
- Close modals/dialogs with ESC (more reliable than finding close button)
- Submit forms with ENTER (when submit button is hard to target)
- Navigate autocomplete/dropdowns with arrow keys
- Trigger keyboard shortcuts

## Key Principles

1. **URL params first** - Always prefer direct URLs over interact commands
   ```bash
   # Good (10x faster)
   open "https://airbnb.com/s/Paris?checkin=2025-12-20&checkout=2025-12-27"

   # Avoid (slow, 4 interactions)
   interact "#location" --input "Paris"
   interact "#checkin" --input "2025-12-20"
   interact "#checkout" --input "2025-12-27"
   interact "[Search]"
   ```
   The `open` command shows URL structure via `inspect`, making it easy to build direct URLs.

   **Use interact only for:** login, checkout, POST forms, wizards

2. **Auto-feedback shows results** - `interact` and `sendkey` automatically show what changed
   ```bash
   interact "Search"              # Automatically waits and snapshots
   interact "#email" --input "x"  # Shows validation/autocomplete
   sendkey esc                    # Closes modal and shows result
   ```

3. **Trust the tool** - Commands wait for stability before showing results
   - Smart contextual wait tracks parent container changes
   - Automatic smart diff (shows additions/deletions)
   - Fallback to full snapshot when state changes (modals, navigation)

4. **Use chrome tool commands** - Built-in commands handle automation needs
   - `open` for navigation + URL discovery
   - `interact` for clicks and inputs (with auto-snapshot)
   - `sendkey` for keyboard input (with auto-snapshot)
   - `snapshot` for manual page capture
   - `inspect` for URL parameter discovery

## Typical Workflows

### Searching/Filtering (URL Construction - PREFERRED)
```bash
# ALWAYS try URL construction first (10x faster than form filling)
open "https://example.com"     # Inspect shows URL parameters

# Build direct URL with parameters (from inspect output)
open "https://example.com/search?q=laptop&category=electronics&price_max=1000"
```

### Login (When interact is necessary)
```bash
# Login requires interact (POST forms, cookies)
open "https://example.com/login"
interact "#email" --input "user@example.com"     # Shows email filled
interact "#password" --input "password"           # Shows password filled
interact "[Login]"                                # Shows dashboard/error
```

### Modal Interactions
```bash
# Open modal
interact '[data-testid="open-modal"]'    # Shows modal content

# Interact within modal
interact "#modal-input" --input "value"  # Shows changes

# Close modal
sendkey esc                               # Shows modal closed
```

### Multi-Step Wizards (When interact is necessary)
```bash
# Step 1
interact "#name" --input "John"
interact "[Next]"                         # Shows step 2

# Step 2
interact "#email" --input "john@ex.com"
interact "[Next]"                         # Shows step 3

# Step 3
interact "[Submit]"                       # Shows confirmation
```

