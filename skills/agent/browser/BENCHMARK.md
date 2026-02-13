# Browser Tool Benchmark Report

Comparison of `run.sh` (bash) vs `cli.js` (Node.js) implementations.

**Test Date:** 2026-01-12
**Test Environment:** macOS, Chrome headless, example.com / google.com

---

## Performance Summary

| Command | bash (run.sh) | Node.js (cli.js) | Winner |
|---------|---------------|------------------|--------|
| help | 0.01s | 0.10s | bash |
| open (cold) | 4.42s | **HUNG** | bash |
| open (warm) | 0.47s | 0.21s | Node.js |
| snapshot | 0.47s | 0.15s | Node.js |
| click (selector) | 0.50s | 0.66s | bash |
| click (coords) | 2.69s | 0.15s | Node.js |
| input | 1.98s | 0.17s | Node.js |
| sendkey | ~1.5s | 0.16s | Node.js |
| tabs | 0.08s | 0.15s | bash |
| screenshot | 0.22s | 0.20s | tie |
| execute | 2.21s | 0.15s | Node.js |
| inspect | ~0.5s | ~0.5s | tie |
| wait | 1.53s | 0.65s | Node.js |
| close | N/A | 0.16s | Node.js |

---

## Critical Issues Found

### Node.js Version (cli.js)

1. **`open` command hangs on cold start**
   - Chrome launches successfully
   - Node.js process never completes
   - Requires manual kill (Ctrl+C)
   - **Severity: CRITICAL**

2. **Auto-snapshot not showing after interactions**
   - `click`, `sendkey` commands show status but no page diff
   - bash version shows full snapshot diff after each action
   - **Severity: HIGH** (breaks feedback loop)

3. **Snapshot diff shows nothing when unchanged**
   - Should display "(no changes)" but outputs nothing
   - **Severity: LOW**

### Bash Version (run.sh)

1. **No `close` command**
   - Cannot programmatically close Chrome
   - `cmd_close` called but undefined
   - **Severity: HIGH**

2. **Slower due to auto-feedback**
   - Every command runs `wait` + `snapshot`
   - Good for visibility, bad for speed
   - **Severity: LOW** (tradeoff)

---

## Feature Comparison

| Feature | bash | Node.js | Notes |
|---------|------|---------|-------|
| open | :white_check_mark: | :x: HUNG | Node.js hangs on cold start |
| snapshot | :white_check_mark: | :white_check_mark: | Both work |
| snapshot --full | :white_check_mark: | :white_check_mark: | Both work |
| click (selector) | :white_check_mark: | :white_check_mark: | Both work |
| click (coords) | :white_check_mark: | :white_check_mark: | Both work |
| input | :white_check_mark: | :white_check_mark: | Both work |
| sendkey | :white_check_mark: | :white_check_mark: | Both work |
| tabs | :white_check_mark: | :white_check_mark: | Both work |
| screenshot | :white_check_mark: | :white_check_mark: | Both work |
| execute | :white_check_mark: | :white_check_mark: | Both work |
| inspect | :white_check_mark: | :white_check_mark: | Both work |
| wait | :white_check_mark: | :white_check_mark: | Both work |
| close | :x: MISSING | :white_check_mark: | bash has no close |
| hover (selector) | :x: | :white_check_mark: | bash not implemented |
| hover (coords) | :white_check_mark: | :white_check_mark: | Both work |
| drag (coords) | :white_check_mark: | :white_check_mark: | Both work |
| drag (selector) | :x: | :white_check_mark: | Node.js only |
| Auto-feedback | :white_check_mark: | :x: PARTIAL | Node.js missing snapshot |

---

## Usability Comparison

### bash (run.sh)

**Pros:**
- Complete auto-feedback after every action
- Smart diff shows exactly what changed
- Works reliably on cold start
- No Node.js dependency for basic operations

**Cons:**
- No `close` command (Chrome lingers)
- Slower due to comprehensive feedback
- Complex bash code (2000+ lines)
- Some features missing (hover selector)

### Node.js (cli.js)

**Pros:**
- Much faster execution (no auto-feedback overhead)
- Has `close` command
- Cleaner code structure
- Supports more interaction modes (drag selector)

**Cons:**
- **CRITICAL: Hangs on cold start**
- Missing auto-snapshot after interactions
- Less visible feedback for users

---

## Recommendations

### Short-term (Fix blockers)

1. **Fix cli.js cold start hang** - Debug `ensureChromeRunning()` / `waitForCdp()`
2. **Add auto-snapshot to cli.js** - After click/input/sendkey/execute
3. **Add `close` command to run.sh** - Or deprecate in favor of cli.js

### Long-term

1. **Choose one implementation** - Maintaining both is overhead
2. **Recommended: cli.js** - After fixing cold start, it's faster and cleaner
3. **Optional: Make feedback configurable** - `--quiet` flag for speed, default for visibility

---

## Raw Test Data

```
# Help command startup
bash:   0.01s
nodejs: 0.10s

# Open (cold start - launching Chrome)
bash:   4.42s (success)
nodejs: HUNG (Chrome started, process stuck)

# Snapshot
bash:   0.47s
nodejs: 0.15s

# Click selector
bash:   0.50s
nodejs: 0.66s

# Click coordinates
bash:   2.69s (includes auto-feedback)
nodejs: 0.15s (no feedback)

# Input
bash:   1.98s
nodejs: 0.17s

# Tabs
bash:   0.08s
nodejs: 0.15s

# Screenshot
bash:   0.22s
nodejs: 0.20s

# Execute
bash:   2.21s (includes snapshot)
nodejs: 0.15s (no snapshot)

# Wait
bash:   1.53s (complex stability check)
nodejs: 0.65s (simple timeout)

# Close
bash:   N/A (command missing)
nodejs: 0.16s
```
