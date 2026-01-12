# Deprecated: Bash Browser Implementation

These files are the original bash implementation of the browser tool, now replaced by `cli.js`.

## Why Deprecated

The bash version (`run.sh`) had several unfixable issues:
- Missing `close` command
- `releaseProfile()` never called, causing orphaned Chrome processes
- Complex 2000+ line bash script difficult to maintain
- Required Python (`py/`) and Node.js (`cdp-cli.js`) helpers

## Replacement

Use `browser/cli.js` instead - a pure Node.js implementation with all issues fixed.

## Files

- `run.sh` - Main bash script (2072 lines)
- `test.sh` - Test script for bash version
- `cdp-cli.js` - CDP interface used by run.sh
- `py/format-inspect.py` - Python formatting helper

## Archived

2026-01-12
