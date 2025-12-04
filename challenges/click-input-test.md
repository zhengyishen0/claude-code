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

### Click Strategies

| Scenario | CSS Selector | --text | --aria | --testid | Notes |
|----------|--------------|--------|--------|----------|-------|
| 1. Close popup | ✅ `button[aria-label="Close"]` | ❌ no text | ✅ "Close" | N/A | In modal context, aria works |
| 2. Open search | ✅ works | ✅ "Anywhere" | ✅ "Search" | ⚠️ varies | aria="Search" on button |
| 4. Select date | ⚠️ complex | ✅ "Check in" | ❌ no aria | N/A | No aria-label, use --text |
| 5. Add guests | ⚠️ complex | ✅ "Who" or "guests" | ❌ no aria | N/A | No aria-label, use --text |
| 6. Apply filters | ❌ class changes | ✅ "Filters" | ❌ no aria | ✅ `category-bar-filter-button` | testid is best |
| 7. Add to wishlist | ⚠️ nth-child needed | ❌ no text | ✅ "Add to wishlist: [listing]" | ✅ `listing-card-save-button` | aria includes listing name |
| 8. Select wishlist | ❌ dynamic | ✅ wishlist name | ✅ "Wishlist for [name], N saved" | N/A | aria includes saved count |
| 9a. Create new wishlist btn | ⚠️ modal | ✅ "Create new wishlist" | ✅ "Create new wishlist" | ✅ `save-to-list-modal-create-new-button` | All strategies work! |
| 9b. Confirm Create btn | ⚠️ modal | ✅ "Create" | ❌ no aria | ✅ `save-to-list-modal-create-new-modal-create-button` | Use text or testid |
| 10. Pagination | ⚠️ `<a>` needs href | ❌ matches prices | ✅ "Next"/"Previous" | N/A | `.click()` doesn't navigate `<a>` |

### Input Strategies

| Scenario | CSS Selector | --text (placeholder) | --aria | --testid | Notes |
|----------|--------------|----------------------|--------|----------|-------|
| 3. Enter location | ✅ `#bigsearch-query-location-input` | ✅ "destinations" | ✅ "Where" | N/A | All strategies work |
| 9. Wishlist name | ⚠️ dynamic | ❌ no placeholder | ❌ no aria | ✅ `save-to-list-modal-name-input` | testid is only option |

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

5. **Critical bug: `.click()` doesn't navigate `<a>` tags** in SPAs - need `window.location.href = el.href`

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
4. For `<a>` navigation: Need to enhance click-element.js to use `location.href`

**For inputs:**
1. Check what's available: `recon` shows `Input: aria="Where"` or `Input: \`name\``
2. Priority: `--testid` > `--aria` > `--text` > CSS selector
3. Always use `--clear` flag for React inputs
