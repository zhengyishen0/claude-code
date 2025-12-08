# Auto-Wait Feature Test

## Overview
Tests the automatic wait and recon functionality after click and input commands.

## Test Setup
```bash
# Ensure auto-mode is enabled (default)
source tools/chrome/config
echo "CHROME_AUTO_MODE=$CHROME_AUTO_MODE"  # Should be "true"
```

## Test Cases

### Test 1: Modal Open Detection
**Site**: GitHub (Settings button opens modal)

**Before (manual chaining)**:
```bash
tools/chrome/run.sh click "[Settings]" + wait "[role=dialog]" + recon
```

**After (auto-mode)**:
```bash
tools/chrome/run.sh click "[Settings]"
# Automatically detects modal opened
# Automatically waits for [role=dialog]
# Automatically recons dialog section only
```

### Test 2: Navigation Detection
**Site**: Any site with links

**Before (manual chaining)**:
```bash
tools/chrome/run.sh click "[Products]" + wait + recon
```

**After (auto-mode)**:
```bash
tools/chrome/run.sh click "[Products]"
# Automatically detects navigation
# Automatically waits for page load
# Automatically recons full page
```

### Test 3: Form Input with Validation
**Site**: Any site with form validation

**Before (manual chaining)**:
```bash
tools/chrome/run.sh input "@Email=invalid" + wait "[role=alert]" + recon
```

**After (auto-mode)**:
```bash
tools/chrome/run.sh input "@Email=invalid"
# Automatically waits for validation messages
# Automatically recons form section
```

### Test 4: Modal Close Detection
**Site**: Any site with closable modals

**Before (manual chaining)**:
```bash
tools/chrome/run.sh click "[X]" + wait "[role=dialog]" --gone + recon
```

**After (auto-mode)**:
```bash
tools/chrome/run.sh click "[X]"
# Automatically detects modal closed
# Automatically waits for dialog to disappear
# Automatically recons main content
```

### Test 5: Inline Update (SPA Interaction)
**Site**: Any SPA with dynamic content

**Before (manual chaining)**:
```bash
tools/chrome/run.sh click "[Load More]" + wait + recon
```

**After (auto-mode)**:
```bash
tools/chrome/run.sh click "[Load More]"
# Automatically waits for DOM changes
# Automatically recons full page
```

## Manual Mode Testing
```bash
# Disable auto-mode
export CHROME_AUTO_MODE=false

# Now requires explicit chaining
tools/chrome/run.sh click "[Settings]"
# Just clicks, no auto-wait or recon

tools/chrome/run.sh click "[Settings]" + wait "[role=dialog]" + recon
# Manual control
```

## Expected Results
- Auto-mode should correctly detect context type (navigation, modal-open, modal-close, inline)
- Wait commands should be automatically executed with appropriate selectors
- Recon should be scoped to relevant sections (dialog, main, form)
- Manual mode should still work with explicit chaining
- No regressions in existing functionality
