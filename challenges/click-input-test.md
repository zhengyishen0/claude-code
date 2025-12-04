# Click & Input Strategy Test Challenge

Test the reliability of different click and input strategies on Airbnb.

## Test Scenarios

### Scenario 1: Close Popup Modal
When visiting Airbnb, a "prices include fees" popup often appears.
- **Goal**: Close the popup
- **Target**: The "Got it" button or close button

### Scenario 2: Open Search Panel
Click on the search area to expand it.
- **Goal**: Open the search input panel
- **Target**: The search bar/location input area

### Scenario 3: Enter Search Location
Type a location into the search input.
- **Goal**: Enter "Griffith Observatory" in location field
- **Target**: Location input field

### Scenario 4: Select Date
Click on the date picker.
- **Goal**: Open check-in date selector
- **Target**: Check-in date button

### Scenario 5: Add Guests
Open guest selector and add guests.
- **Goal**: Open guest selector panel
- **Target**: Guests button

### Scenario 6: Apply Filters
On search results page, open filters panel.
- **Goal**: Open the filters modal
- **Target**: Filters button

### Scenario 7: Add to Wishlist
Save a listing to wishlist.
- **Goal**: Click the heart/save button on a listing
- **Target**: Wishlist button on a listing card

### Scenario 8: Select Wishlist
Choose which wishlist to save to.
- **Goal**: Select a specific wishlist from the modal
- **Target**: Wishlist item in modal

### Scenario 9: Create New Wishlist
Create a new wishlist with a custom name.
- **Goal**: Click "Create new wishlist", enter name, click "Create"
- **Target**: Create button, name input, confirm button

### Scenario 10: Navigate Pagination
Go to next page of results.
- **Goal**: Click next page
- **Target**: Next/page number button

## Test Matrix

For each scenario, test these strategies and record success/failure:

### Click Strategies (Verified December 3, 2025)

| Scenario | CSS Selector | --text | --aria | --testid | Recon Output | Notes |
|----------|--------------|--------|--------|----------|--------------|-------|
| 1. Close popup | ✅ | ❌ | ✅ "Close" | N/A | `[@Close](#button)` | Modal may not appear |
| 2. Search button | N/A | N/A | ❌ (after nav) | ✅ | `[@Search](#structured-search-input-search-button)` | testid is reliable |
| 4. Select date | N/A | ✅ "When" | ❌ | N/A | `[WhenAdd dates](#button)` | text only, no aria |
| 5. Add guests | N/A | ✅ "Who" | ❌ | N/A | `[WhoAdd guests](#button)` | text only, no aria |
| 5b. +/- steppers | N/A | N/A | ✅ "increase/decrease" | ✅ | `[@increase value](#stepper-adults-increase-button)` | Both work |
| 6. Filters | N/A | ✅ "Filters" | ✅ | ✅ | `[Filters](#category-bar-filter-button)` | All work |
| 7. Add to wishlist | N/A | ❌ | ✅ "Add to wishlist" | ✅ | `[@Add to wishlist: Home](#listing-card-save-button)` | No visible text |
| 8. Select wishlist | N/A | ❌ | ✅ "Wishlist for" | N/A | `[@Wishlist for Iceland 2025, 5 saved](#button)` | aria only |
| 9. Create wishlist | N/A | ✅ | ✅ | ✅ | `[Create new wishlist](#save-to-list-modal-create-new-button)` | All work |
| 10. Pagination | N/A | ❌ | ✅ "Next"/"Previous" | N/A | `[@Previous](#button)`, `[Next](/s/homes)` | Next is `<a>` link |

### Input Strategies (Verified December 3, 2025)

| Scenario | CSS Selector | --text | --aria | --testid | Recon Output | Notes |
|----------|--------------|--------|--------|----------|--------------|-------|
| 3. Enter location | ✅ `#bigsearch-query-location-input` | N/A | ✅ "Where" | N/A | `Input: aria="Where" (search)` | aria works great |
| 9. Wishlist name | N/A | ❌ | ❌ | ✅ | `Input: testid="save-to-list-modal-name-input"` | testid only |

## Instructions

1. Start fresh: `chrome-cli open "https://www.airbnb.com"`
2. For each scenario, try each click strategy
3. Record: ✅ (works), ❌ (fails), ⚠️ (works sometimes)
4. Note which selector/text/aria/testid value you used
5. For input tests, also test with `--clear` flag

## Test Results Summary (December 2025)

### Click Strategy Reliability

| Strategy | Success Rate | Best For |
|----------|--------------|----------|
| **--testid** | 5/5 (100%) | Most reliable when available (~40% of elements on Airbnb) |
| **--aria** | 6/11 (55%) | Wishlist buttons, modals, pagination. Not on date/guest/filter buttons |
| **--text** | 8/11 (73%) | User-visible buttons, but can be ambiguous |
| **CSS Selector** | 4/11 (36%) | Stable IDs only, fails on dynamic classes |

### Input Strategy Reliability

| Strategy | Success Rate | Best For |
|----------|--------------|----------|
| **--aria** | 1/2 (50%) | Search location input has aria="Where" |
| **--text** | 1/2 (50%) | Search has placeholder "Search destinations" |
| **--testid** | 1/2 (50%) | Wishlist name input ONLY has testid |
| **CSS Selector** | 1/2 (50%) | Works when ID is stable |

### Key Findings

1. **`--testid` is most reliable** when available. Airbnb uses it on key interactive elements

2. **`--aria` works great for wishlist flows**:
   - `--aria "Add to wishlist: [listing]"` - heart buttons include listing name
   - `--aria "Wishlist for [name], N saved"` - selecting existing wishlist
   - `--aria "Create new wishlist"` - create button in modal
   - `--aria "Close"` - modal close buttons
   - `--aria "Next"` / `--aria "Previous"` - pagination

3. **`--aria` does NOT exist on**:
   - Date picker ("When" / "Check in" buttons) - use `--text`
   - Guest selector ("Who" / "Add guests") - use `--text`
   - Filters button - use `--testid "category-bar-filter-button"`

4. **`--text` has ambiguity risks** - "2" matched a price instead of page number

5. **Fixed: `.click()` now navigates `<a>` tags** - click-element.js updated to use `window.location.href = el.href` for `<a>` tags

6. **Always use `--clear` for inputs** - React inputs need clearing before setting new values

### Aria-Label Quick Reference

| Element | aria-label Value |
|---------|------------------|
| Search button | "Search" |
| Wishlist heart | "Add to wishlist: [listing name]" |
| Select wishlist | "Wishlist for [name], N saved" |
| Create new wishlist | "Create new wishlist" |
| Close modal | "Close" |
| Next page | "Next" |
| Previous page | "Previous" |
| Clear input | "Clear" |

### Recommendations

**For clicks:**
1. Priority: `--testid` > `--aria` > `--text` > CSS selector
2. Use `--aria` for: wishlist buttons, modals, pagination
3. Use `--text` for: date/guest buttons when no aria-label exists
4. For `<a>` navigation: Fixed in click-element.js to use `location.href`

**For inputs:**
1. Check what's available: `recon` shows `Input: aria="Where"` or `Input: \`name\``
2. Priority: `--testid` > `--aria` > `--text` > CSS selector
3. Always use `--clear` flag for React inputs

## Button Format in Recon Output

The `recon` command now shows buttons with clear separation of text vs aria-label:

```
[text@aria](#testid)
```

**Format examples:**
- `[@Clear Input](#button)` → aria-label only, no visible text → use `--aria "Clear Input"`
- `[WhenAdd dates](#button)` → text only, no aria → use `--text "When"`
- `[Search](#structured-search-input-search-button)` → text (=aria), has testid → use `--testid`
- `[@Add to wishlist: Apartment](#listing-card-save-button)` → aria + testid → use either

**How to read:**
- `@` at start = aria-label only (no visible text)
- `text@aria` = both exist and differ
- `text` alone = no aria-label, only visible text
- `#selector` = data-testid (or id fallback)

## Smart Click Command

The `click` command now accepts the recon format directly and auto-detects the best strategy:

```bash
# Copy from recon output and use directly
chrome-cli-plus click "[@Search](#structured-search-input-search-button)"  # → uses testid
chrome-cli-plus click "[Filters](#category-bar-filter-button)"             # → uses testid
chrome-cli-plus click "[@Add to wishlist](#listing-card-save-button)"      # → uses testid
chrome-cli-plus click "[@Close](#button)"                                  # → uses aria (#button = no testid)
chrome-cli-plus click "[When](#button)"                                    # → uses text

# Priority: testid > aria > text > href
```

**Note:** Recon collapses whitespace (e.g., "WhenAdd dates"), but you can use partial text like `[When](#button)` for cleaner commands.
