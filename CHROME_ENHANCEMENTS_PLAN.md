# Chrome Tool Enhancement Plan

## Completed Commands (Ready to Integrate)

The following commands were implemented and tested with chrome-cli. They need to be adapted to work with the new CDP architecture:

### Navigation & Keyboard Commands
1. **enter** - Send Enter key (complements esc for form submission)
   - Triggers form submission
   - Works with autocomplete and search boxes

### Tab Management Commands
2. **tabs** - List all Chrome windows and tabs
   - Shows window IDs and tab IDs
   - Essential for multi-tab workflows

3. **info [TAB_ID]** - Show current or specific tab details
   - Displays tab ID, URL, title, loading state
   - Optional tab ID parameter

4. **activate TAB_ID** - Switch to specific tab
   - Brings specified tab to foreground

5. **close [-w] [TAB_ID]** - Close tabs/windows
   - `-w` flag to close windows instead of tabs
   - Optional tab/window ID parameter

### Navigation Commands
6. **reload [TAB_ID]** - Reload current or specific tab
7. **back [TAB_ID]** - Navigate back in history
8. **forward [TAB_ID]** - Navigate forward in history

### Advanced Commands
9. **execute 'JS' [-t ID]** - Execute arbitrary JavaScript
   - Escape hatch for edge cases
   - Optional tab ID parameter
   - Returns result of last expression

## Screenshot Enhancement (Proposed - Not Implemented)

### Goal
Make `chrome screenshot` Chrome-specific and intelligent, supporting tab IDs and fuzzy title matching.

### Requirements

**Listing (no arguments):**
```bash
chrome screenshot
```
Output format:
```
[Window: 615744953] [Tab: 615745011] Search results - Gmail
[Window: 615744953] [Tab: 615745010] New Tab
[Window: 615732751] [Tab: 615734567] Boston to Los Angeles - Google Flights
```

**Input Types:**
- **Window ID**: `chrome screenshot 615744953` → Screenshot directly (no activation)
- **Tab ID**: `chrome screenshot 615745011` → Activate tab, get window ID, screenshot
- **Fuzzy title**: `chrome screenshot "Gmail"` → Match title, activate tab, screenshot

**Fuzzy Matching:**
- Case-insensitive substring match first
- Fall back to character-in-order fuzzy match
- If multiple matches, show list and error

**Key Behavior:**
1. Save current active tab ID
2. Activate target tab (if needed)
3. Get window ID for the tab
4. Screenshot the window using `screencapture -l <window_id>`
5. Convert to JPEG + output base64
6. **Restore original active tab** (critical for non-intrusive automation)

### Implementation Strategy

**DO NOT copy code. Compose existing commands:**
- Use `$CHROME` abstraction (works with both chrome-cli and CDP)
- Call internal `cmd_*` functions, never chrome-cli directly
- Reuse screenshot tool's capture/JPEG conversion if possible

### CDP Compatibility Notes

Since CDP only provides `open` and `execute`, the tab management commands (tabs, info, activate) need to be implemented using JavaScript execution via CDP. The screenshot command should:
1. Query tabs using JavaScript via `$CHROME execute`
2. Activate tabs using JavaScript via `$CHROME execute`
3. Get window IDs (may need platform-specific approach for headless Chrome)
4. Use existing screenshot capture mechanism

## Files Created

- `claude-tools/chrome/js/send-enter.js` - Enter key handler
- `claude-tools/chrome/py/screenshot.py` - Chrome-specific screenshot (needs revision for CDP)

## Implementation Status

**Completed:**
- All 9 commands implemented with chrome-cli
- Full README documentation
- Organized help text with categories

**Needs Adaptation:**
- All commands need to work with `$CHROME` abstraction (chrome-cli OR CDP)
- Tab management commands need JavaScript implementation for CDP mode
- Screenshot enhancement needs to be implemented with tab activation/restoration

## Next Steps

1. Adapt tab management commands to work via `$CHROME execute` with JavaScript
2. Test all commands in both chrome-cli and CDP modes
3. Implement screenshot enhancement with proper abstraction
4. Update README with CDP compatibility notes
