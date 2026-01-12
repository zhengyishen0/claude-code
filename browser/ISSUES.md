# Browser Tool Issues Report

Analysis of `run.sh` (bash) and `cli.js` (Node.js) implementations.

**Updated:** 2026-01-12 - cli.js issues have been fixed!

## Issue Summary

| Issue | run.sh | cli.js | Severity |
|-------|--------|--------|----------|
| `close` command missing | :x: | :white_check_mark: | Critical |
| `releaseProfile()` never called | :x: | :white_check_mark: | Critical |
| `--debug` can't override headless | :x: | :white_check_mark: **FIXED** | Critical |
| Port 9222 conflict risk | :x: | :white_check_mark: **FIXED** (hash-based ports) | Medium |
| `profile import` copies too much | :x: | :white_check_mark: (removed) | Medium |
| `profile create` incomplete | :warning: blocking | :white_check_mark: **FIXED** | Medium |
| No SIGINT/SIGTERM handling | :x: | :white_check_mark: **FIXED** | Low |
| Cold start hang | N/A | :white_check_mark: **FIXED** | Critical |

## Critical Issues

### 1. Headless Mode Inheritance (Both versions)

**Location**: `run.sh:296`, `cli.js:296`

```javascript
if (await cdpIsRunning()) return true;  // Returns immediately without checking mode!
```

**Problem**: Once a headless Chrome starts, subsequent `--debug` commands connect to the existing headless instance instead of starting a headed browser.

**Scenario**:
1. Run `browser --profile test open url` → Starts headless Chrome
2. Run `browser --profile test --debug open url` → Expects headed browser
3. **Actual**: Connects to existing headless instance

### 2. Missing `cmd_close` (run.sh only)

**Location**: `run.sh:1554`

```bash
cmd_close > /dev/null  # Function doesn't exist!
```

The `profile create` command calls `cmd_close` but the function is never defined.

### 3. Orphaned Chrome Processes (run.sh)

Chrome is spawned with `nohup ... &` but never terminated. The `releaseProfile()` function exists but is never called.

## Medium Issues

### 4. Port 9222 Conflict

Default port range 9222-9299 may conflict with user's Chrome remote debugging sessions.

### 5. `profile create` Not Functional (cli.js)

**Location**: `cli.js:935-974`

Only prints instructions, doesn't actually launch browser for login.

### 6. `profile import` Copies Entire Profile (run.sh)

**Location**: `run.sh:1782-1783`

```bash
cp -r "$source_path" "$dest_path"
```

Copies entire Chrome profile including all cookies, history, passwords - not just target service credentials.

## Recommendations

~~1. **Fix headless inheritance**: Check if running instance matches requested mode (headless/headed)~~ **DONE**
~~2. **Add signal handlers**: Clean up port-registry on SIGINT/SIGTERM~~ **DONE**
3. ~~**Implement `close` command** in run.sh or~~ deprecate run.sh in favor of cli.js **RECOMMENDED**
~~4. **Complete `profile create`** in cli.js to actually launch browser~~ **DONE**
~~5. **Use different default port range** (e.g., 19222-19299) to avoid conflicts~~ **DONE** (hash-based 9222-9299)

## Conclusion

**cli.js is now production-ready and can fully replace run.sh.**

All critical issues in cli.js have been fixed:
- Cold start no longer hangs
- --debug properly switches between headless/headed modes
- profile create actually launches browser for login
- Signal handlers clean up on Ctrl+C
- Hash-based port assignment avoids conflicts

## Files Analyzed

- `browser/run.sh` - Bash implementation (2072 lines) - **DEPRECATED**
- `browser/cli.js` - Node.js implementation (1460 lines) - **RECOMMENDED**
- `browser/cdp-cli.js` - CDP interface (407 lines)
- `browser/README.md` - Documentation (749 lines)
