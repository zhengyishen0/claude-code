# screenshot

Background window capture for macOS with automatic dual-version output

## Commands

### `<app_name|window_id> [output_path]`

Captures a screenshot and **automatically saves TWO versions**:
1. **screenshot.png** - 0.5 downscale + Clop (268KB) - Default for AI analysis
2. **screenshot-full.png** - Full-res + Clop (979KB) - For detailed review

**Arguments:**
- **app_name**: Application name (case-insensitive partial match). Examples: "Chrome", "Google Chrome", "Terminal"
- **window_id**: Numeric window ID from `--list` for exact targeting
- **output_path**: Optional file path (default: `./tmp/screenshot-TIMESTAMP.png`)

Returns both screenshot paths.

### `--list`

Lists all capturable windows with their IDs, application names, and titles.

Useful for finding the exact app name or window ID to use for capture.

## Key Principles

1. **No activation required** - Captures windows in the background using macOS CGWindowID
2. **Dual-output always** - Always saves both downscaled (AI-optimized) and full-res versions
3. **AI-first workflow** - Downscaled version is default for analysis, full version available when needed
4. **No decisions needed** - Simple interface with no flags or options
5. **Project-local storage** - Screenshots saved to `./tmp/` by default

## Dual-Version Strategy

**Every capture produces TWO files:**

| File | Resolution | Size | Purpose |
|------|------------|------|---------|
| `screenshot.png` | 1694×1052 | 268KB | AI analysis (default) |
| `screenshot-full.png` | 3124×1940 | 979KB | Detailed review |

**Why dual output:**
- **AI reads downscaled by default** - 268KB is fast to load, fully readable for automation
- **Full version available** - When AI needs to verify fine details or for human review
- **No decision paralysis** - Always get both, choose which to use based on need

**Compression breakdown:**
- Original raw capture: ~2.8M (3124×1940)
- Clop optimization: 65-70% reduction (lossless PNG compression)
- 0.5 downscale: Additional 75% pixel reduction
- **Combined: 90% total reduction** with full AI readability

## Technical Implementation

- Uses PyObjC + Quartz framework to query macOS window server for CGWindowIDs
- Captures via native `screencapture -l <window_id>` command
- Downscales using `sips -Z` (maintains aspect ratio)
- Optimizes with Clop app (lossless PNG compression via zopfli/oxipng)
- Requires `pyobjc-framework-Quartz` Python package and Clop app
- macOS only (uses Quartz framework)

## Examples

```bash
# Capture by app name (automatically saves both versions)
screenshot "Google Chrome"
# → /path/to/project/tmp/screenshot-20251210-120530.png (268KB - for AI)
# → /path/to/project/tmp/screenshot-20251210-120530-full.png (979KB - for review)

# Capture by window ID for exact targeting
screenshot 29725
# → /path/to/project/tmp/screenshot-20251210-120545.png (268KB)
# → /path/to/project/tmp/screenshot-20251210-120545-full.png (979KB)

# Custom output path
screenshot 29725 /tmp/my-screenshot.png
# → /tmp/my-screenshot.png (268KB)
# → /tmp/my-screenshot-full.png (979KB)

# List all windows to find app name or window ID
screenshot --list
# Google Chrome
# --------------------------------------------------------------------------------
#   [29725     ] Airbnb | Vacation rentals, cabins, beach houses, & more
#   [1411      ] Tmux Cheat Sheet & Quick Reference
```

## Workflow

**AI reads downscaled by default:**
```bash
# Capture screenshot
screenshot_path=$(screenshot 29725 | head -1)  # Gets downscaled version

# AI analyzes the 268KB version
# If AI needs more detail, read the -full.png version
```

**Both versions always available:**
- First output line: downscaled version (for AI)
- Second output line: full-resolution version (for review)

## Integration with Browser Automation

Works seamlessly with the chrome tool for non-intrusive debugging:

```bash
# Open page in background
chrome open "https://example.com"

# Wait for content
chrome wait

# Screenshot without activating window
screenshot "Google Chrome"
```
