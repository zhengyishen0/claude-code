---
name: screenshot
description: Capture screenshots for AI vision analysis. Use when you need to see what's on screen, verify UI state, or capture visual information.
---

# Screenshot Tool

Capture screen for AI vision analysis.

## Command

```bash
screenshot [app_name]
```

## Examples

```bash
screenshot                    # Capture entire screen
screenshot "Google Chrome"    # Capture specific app window
screenshot "Finder"           # Capture Finder window
screenshot "Terminal"         # Capture Terminal window
```

## Output

Returns path to saved image file. Use the Read tool to view:

```bash
screenshot "Safari"
# Output: /tmp/screenshot-2025-02-11-12-34-56.png

# Then use Read tool to view the image
```

## When to Use

- Verify UI state after browser automation
- See what's on screen when user describes visual issue
- Capture error dialogs or notifications
- Debug visual layout problems

## Browser Screenshots

For web page screenshots specifically, prefer:

```bash
browser screenshot              # Captures browser viewport
browser screenshot --full       # Full page capture
```

The `browser screenshot` command is optimized for web content and provides more control (viewport size, quality, format).
