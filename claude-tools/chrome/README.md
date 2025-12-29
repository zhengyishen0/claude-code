# Chrome Tool

Browser automation with React/SPA support

## Usage

```bash
claude-tools chrome --profile <name> <command> [args...]
```

**Important:** The `--profile` flag is required for all automation commands to prevent accidental use of your personal Chrome.

**Modes:**
- `--profile <name>`: Headless automation with saved credentials (default)
- `--profile <name> --debug`: Headed mode for debugging (visible window)
- `--debug`: Manual testing using system Chrome (no profile)

## Commands

Commands are organized by usage frequency:

**Primary (most common):**
- `open` - Navigate and discover structure
- `click` - Click by selector or coordinates
- `input` - Set input value (React-compatible)
- `hover` - Hover at coordinates
- `drag` - Drag from coordinates to coordinates

**Secondary (frequent):**
- `profile` - Manage credential profiles
- `tabs` - Manage browser tabs

**Utility (advanced):**
- `snapshot` - Capture page state
- `inspect` - Discover URL parameters
- `wait` - Wait for stability/element
- `sendkey` - Send keyboard input
- `execute` - Execute JavaScript

**Visual Commands (CDP):**
- `screenshot` - Capture page for AI vision
- Legacy `pointer` commands (use click/hover/drag instead)

---

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

### click
Click element by selector or coordinates

```bash
click SELECTOR [--index N]     # Click by selector
click X Y                       # Click at coordinates
```

**Auto-feedback behavior:**
1. Clicks element (or coordinates)
2. Waits for page to react with smart contextual wait
3. Shows snapshot diff automatically

**Options:**
- `--index N`: Select Nth match when multiple elements found (selector mode only)

**Examples:**
```bash
click "Search"                  # Click by text, shows results
click "#submit"                 # Click by CSS selector
click "[Submit]" --index 2      # Click 2nd submit button
click 600 130                   # Click at pixel coordinates (vision-based)
```

**When to use click:**
- Buttons, links, checkboxes
- Login/submit actions
- Navigation that requires interaction

**When NOT to use click:**
- Search/filter forms → Use URL construction instead (10x faster)
- Simple navigation → Use `open` with direct URLs

---

### input
Set input value (React-compatible)

```bash
input SELECTOR VALUE [--index N]
```

**Auto-feedback behavior:**
1. Sets input value using React-safe method
2. Dispatches input/change events
3. Waits for validation/reactions
4. Shows snapshot diff automatically

**Options:**
- `--index N`: Select Nth match when multiple inputs found

**Examples:**
```bash
input "#email" "user@example.com"    # Fill input, shows validation
input "Search" "query text"          # Fill search box by text
input "[name='phone']" "555-1234"    # Fill by attribute
```

**Why React-compatible:**
- Uses native property setters (not just .value)
- Triggers proper React state updates
- Works with React, Vue, Angular forms

---

### hover
Hover at coordinates (for dropdowns, tooltips)

```bash
hover X Y
```

**Auto-feedback behavior:**
1. Moves mouse to coordinates
2. Waits for hover effects
3. Shows snapshot diff (dropdowns, tooltips revealed)

**Examples:**
```bash
hover 400 300                   # Hover at coordinates
screenshot                      # See what appears (dropdown menu, etc.)
```

**When to use hover:**
- Revealing dropdown menus
- Showing tooltips
- Triggering hover-based UI

**Note:** Selector-based hover (`hover "Menu"`) not yet implemented - use coordinates for now.

---

### drag
Drag from one coordinate to another

```bash
drag X1 Y1 X2 Y2
```

**Auto-feedback behavior:**
1. Press mouse at start coordinates
2. Drag to end coordinates
3. Release mouse
4. Shows snapshot diff (new position)

**Examples:**
```bash
drag 100 200 300 400            # Drag slider, move element
screenshot                      # See new state
```

**When to use drag:**
- Sliders, range controls
- Drag-and-drop elements
- Sortable lists

**Note:** Selector-based drag not yet implemented - use coordinates only.


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

### tabs
Manage browser tabs (list, activate, close)

```bash
tabs                    # List all tabs
tabs activate <index>   # Switch to tab by index
tabs close <index>      # Close tab by index
```

**Behavior:**
- Lists only page tabs (filters out service workers and extensions)
- Uses simple numeric index [0], [1], [2] for easy reference
- Shows URL and title for each tab

**Examples:**
```bash
tabs                    # [0] https://google.com
                        #     Google
                        # [1] https://github.com
                        #     GitHub

tabs activate 1         # Switch to GitHub tab
tabs close 0            # Close Google tab
```

**Use cases:**
- Manage multiple tabs when working across different sites
- Close tabs to clean up after automation
- Switch between tabs for comparison

### execute
Execute JavaScript code (auto-runs wait and snapshot)

```bash
execute <javascript>    # Execute inline JavaScript
execute --file <path>   # Execute from file
```

**Auto-feedback behavior:**
1. Executes the JavaScript code
2. Shows the return value
3. Waits for page to react
4. Shows snapshot diff automatically

**Return values:**
- Strings: Shown as-is
- Objects/Arrays: Formatted as JSON

**Examples:**
```bash
execute "document.title"                              # Returns: "Google"
execute "document.querySelectorAll('a').length"       # Returns: 42
execute "({title: document.title, url: location.href})"  # Returns: {"title":"Google","url":"https://google.com"}
execute --file extract-data.js                        # Execute multi-line script
```

**When to use execute:**
- Extract data from the page (titles, URLs, counts)
- Manipulate DOM when interact doesn't fit (rare)
- Run complex JavaScript logic from a file

**When NOT to use execute:**
- Simple clicks/inputs → Use `interact` instead
- Keyboard events → Use `sendkey` instead

### profile
Manage browser profiles for authentication

```bash
profile                  # List all profiles
profile <name> [url]     # Open headed browser for login
profile rename OLD NEW   # Rename a profile
```

**Behavior:**
- Each profile has separate cookies/sessions
- Headless by default, headed with `profile <name>`
- Use `--profile <name>` flag on other commands
- **Profile locking:** Only one session can use a profile at a time

**Profile Locking:**
Profiles are automatically locked when in use to prevent conflicts between multiple agents or sessions:

```bash
# Session 1 (Agent A)
chrome --profile amazon-account open "https://amazon.com"
# ✓ Profile locked, assigned CDP port 9222

# Session 2 (Agent B) - tries to use same profile
chrome --profile amazon-account open "https://amazon.com"
# ✗ ERROR: Profile 'amazon-account' is already in use
#
#   Details:
#     Process ID: 12345
#     CDP Port: 9222
#     Running for: 5m 23s
```

**For parallel agents:** Create separate profiles with different accounts:
```bash
# Setup: Create profiles for parallel work (different Amazon accounts!)
profile amazon-buyer1@test.com https://amazon.com
profile amazon-buyer2@test.com https://amazon.com

# Optional: Rename for convenience
profile rename amazon-buyer1@test.com amazon-buyer-1
profile rename amazon-buyer2@test.com amazon-buyer-2

# Use: Each agent gets dedicated account (no conflicts)
chrome --profile amazon-buyer-1 ...  # Agent 1
chrome --profile amazon-buyer-2 ...  # Agent 2
```

**Naming convention:** `<app/domain>-<login-identifier>` (e.g., `gmail-alice@gmail.com`, `amazon-username`)
- Use actual login credential by default (unambiguous)
- Rename to friendly names if desired (e.g., `gmail-personal`)

**Important:** If you only have ONE account, you CANNOT run parallel agents. Profile locking prevents this.

**Examples:**
```bash
profile                           # List: work, personal
profile work https://gmail.com    # Open headed Chrome for login
# ... log in manually ...

# Use the profile
claude-tools chrome --profile work open "https://gmail.com"
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

## Visual Commands (CDP)

Vision-based automation using screenshots and coordinates. No CSS selectors needed!

### screenshot
Capture page screenshot optimized for AI vision

```bash
chrome screenshot [options]
```

**Auto-generates path:** `/tmp/screenshot-YYYY-MM-DD-HH-MM-SS.jpg`

**Options:**
- `--width=N` - Viewport width (default: 1200)
- `--height=N` - Viewport height (default: 800)
- `--quality=N` - JPEG quality 1-100 (default: 70)
- `--full` - Capture full page
- `--png` - PNG format instead of JPEG

**Output:**
```
Screenshot saved: /tmp/screenshot-2025-12-27-12-34-56.jpg
Use Read tool to view the image.
```

**Examples:**
```bash
chrome screenshot                           # Optimized: 1200x800, ~1,280 tokens
chrome screenshot --width=800               # Smaller: 800x600, ~640 tokens
chrome screenshot --full                    # Full page capture
```

**Token Cost:** `(width × height) / 750`

### pointer
Interact using pixel coordinates from screenshots

```bash
chrome pointer click <x> <y>                # Click at coordinates
chrome pointer hover <x> <y>                # Hover at coordinates
chrome pointer drag <x1> <y1> <x2> <y2>     # Drag from->to
```

**Examples:**
```bash
chrome pointer click 237 267                # Click button
chrome pointer hover 400 300                # Hover over menu
chrome pointer drag 100 200 300 400         # Drag slider
```

### Vision Workflow

1. **Screenshot** - Auto-generates path, outputs location
2. **Read** - AI uses Read tool to view the image
3. **Analysis** - AI identifies element coordinates
4. **Pointer** - Click/hover/drag using coordinates

**No CSS selectors needed!** The AI sees the page and tells you coordinates.

**Example:**
```bash
# 1. Take screenshot
chrome screenshot
# Output:
#   Screenshot saved: /tmp/screenshot-2025-12-27-12-34-56.jpg
#   Use Read tool to view the image.

# 2. AI uses Read tool to view the image

# 3. AI analyzes and says: "Search button is at (600, 130)"

# 4. Click using coordinates
chrome pointer click 600 130

# 5. Verify result
chrome screenshot
```

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

