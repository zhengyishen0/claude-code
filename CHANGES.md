# Diff Improvements

## Changes Made

### 1. State-Based Snapshot Comparison

**Problem:** Modals and overlays showed everything as "removed" because smart mode compared expanded content against collapsed content.

**Solution:**
- Added generic page state detection in `js/detect-page-state.js`
- Detected states (universal patterns):
  - `dialog` - `[role="dialog"]` (ARIA standard)
  - `overlay` - Large fixed/absolute positioned elements (date pickers, filters, menus)
  - `dropdown` - `[role="combobox"][aria-expanded="true"]` or visible `[role="listbox"]`
  - `base` - Default page state
- Snapshot filenames now include state: `url-state-timestamp.md`
- Diff only compares snapshots with matching state
- Example: `www.airbnb.com-base-1234.md` vs `www.airbnb.com-dialog-1234.md`

**Universality:** ✅ Uses ARIA roles and generic CSS patterns - works on any website

**Impact:** Eliminates false "removed" diffs when modals open.

---

### 2. Default to Full Mode for Diff

**Problem:** Smart mode's collapsed sections hide changes that diff should show.

**Solution:**
- When `--diff` is used, default to `--full` mode (unless `--smart` is specified)
- Rationale: Diff already reduces noise by showing only changes
- New flag: `--smart` to override back to smart mode when using diff

**Before:**
```bash
recon --diff          # smart mode (collapsed)
recon --diff --full   # full mode
```

**After:**
```bash
recon --diff          # full mode (new default)
recon --diff --smart  # smart mode (if needed)
```

**Universality:** ✅ Generic behavior change - works for all websites

**Impact:** Diff output shows actual content changes, not just section presence.

---

### 3. Improved Wait for Lazy Loading

**Problem:** Footer content loads after DOM appears "stable", causing false diffs.

**Solution:**
- Added `--network` flag to `wait` command
  - Waits for network idle (no active resource requests)
  - Uses standard `performance.getEntriesByType('resource')` API
- Increased DOM stability threshold from 2 checks (0.6s) to 4 checks (1.2s)
  - Gives lazy-loaded content more time to appear
  - More reliable for SPA frameworks (React, Vue, Angular, etc.)

**Usage:**
```bash
wait --network        # Wait for network + DOM stability
wait                  # Just DOM stability (improved threshold)
```

**Universality:** ✅ Uses Web Performance API - works for all websites and SPAs

**Impact:** Reduces noise from lazy-loaded content (footers, ads, analytics, etc.)

---

## Testing

To test these improvements:

```bash
# Clean slate
rm -rf /tmp/recon-snapshots/*

# Test 1: State-based snapshots
tools/chrome/run.sh open "https://www.airbnb.com"
tools/chrome/run.sh input '#bigsearch-query-location-input' 'Paris' + wait + recon --diff
# Should compare base state vs search state (not show everything as removed)

# Test 2: Full mode default
tools/chrome/run.sh click '[data-testid="option-0"]' + wait + recon --diff
# Should show full content changes, not just section headers

# Test 3: Network wait
tools/chrome/run.sh open "https://www.airbnb.com" + wait --network + recon
# Should wait for lazy footer content to load
```

## Expected Improvements

1. **No more false "everything removed" diffs** when modals open
2. **More meaningful diff output** with full content by default
3. **Stable footer content** with better wait logic
4. **Cleaner comparisons** by state-matching snapshots

## Universality Summary

All changes use **generic web standards** and work across any website:

| Feature | Technology | Universal? |
|---------|-----------|------------|
| State Detection | ARIA roles (`role="dialog"`, `role="combobox"`), CSS positioning | ✅ Yes |
| Full Mode Default | Behavioral change | ✅ Yes |
| Network Wait | Web Performance API | ✅ Yes |
| DOM Stability | DOM mutation detection | ✅ Yes |

**No site-specific logic** - these improvements work on:
- E-commerce sites (Amazon, eBay, Shopify)
- Travel sites (Airbnb, Booking.com, Expedia)
- SaaS apps (Salesforce, Notion, Linear)
- Any website with modals, dropdowns, or lazy-loaded content
