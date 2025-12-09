# Claude Code Project

## Development Workflow

**Default**: Use git worktrees for all code changes to maintain branch isolation.

Before making edits:
1. **Check current branch**: `git branch --show-current`
2. **If on `main`**: Run `tools/worktree/run.sh create feature-name`
3. **Work in worktree**: Use absolute paths to make changes
4. **Merge when done**: Merge back to main and remove worktree

**Creating a worktree with Claude**:
```bash
tools/worktree/run.sh create feature-name
# Creates worktree at ../claude-code-feature-name
# Prints absolute path for use in current session
# Grant permission when prompted to access the worktree
```

**Using the worktree**:
Use absolute paths when working in worktrees:
```bash
# Good: absolute paths
/Users/you/Codes/claude-code-feature-name/src/file.js

# Avoid: cd and relative paths
cd ../claude-code-feature-name && edit src/file.js
```

**Cleanup after merge**:
```bash
cd ../claude-code
git merge feature-name
tools/worktree/run.sh remove feature-name
```

**Exception**: Skip worktrees for trivial changes (typos, docs, single-line fixes).

**Automatic Triggering**: When a user requests feature work and you're on main branch, proactively suggest and run `tools/worktree/run.sh create <feature-name>`.

## Tool Design Principles

When creating tools:
1. **Self-documenting** - Tools document themselves via `help` command
2. **Help as default** - Running with no args shows help + prereq check
3. **No separate doc files** - Brief description in CLAUDE.md, full docs in tool's help
4. **Prereq check on first use** - Tools check/install dependencies when run without args
5. **Standard entry point** - Each tool uses `run.sh`, name derived from folder

## Command Execution Guidelines

Avoid wrapping tool commands in bash variables - use direct tool entry points instead.

**Bad** (triggers permission prompts):
```bash
JS_CODE=$(cat tools/chrome/js/click-element.js) && chrome-cli execute '...'
```

**Good** (pre-approved):
```bash
tools/chrome/run.sh click "[Homes]"
chrome-cli execute 'document.querySelector("button").click()'
```

## Available Tools

<!-- TOOLS:AUTO-GENERATED -->

Universal entry: `tools/run.sh <tool> [command] [args...]`

### chrome
Browser automation with React/SPA support

Run `tools/chrome/run.sh` for full help.

**Commands:** snapshot, open, wait, click, input, esc, help

**Key Principles:**
1. URL params first - always prefer direct URLs over clicking
2. Snapshot first - understand page before interacting
3. Track changes with --diff - see what changed after interactions
   - `snapshot` - capture current state (always saves full content)
   - `snapshot --diff` - show changes vs previous
4. Chain with + - action + wait + snapshot --diff in one call
5. State-based snapshots - auto-detects base/dropdown/overlay/dialog
6. Wait for specific element - not just any DOM change
7. Use --gone when expecting element to disappear
8. Use --network for lazy content - wait for footer/ads to load

**Typical workflow:**
```bash
open "https://example.com" + wait + snapshot
input '#search' 'query' + wait + snapshot --diff
click '[data-testid="btn"]' + wait + snapshot --diff
```

### worktree
Git worktree management for isolated feature development

Run `tools/worktree/run.sh` for full help.

**Commands:** create, rename, list, remove, help

**Key Usage:**
- Create worktree: `tools/worktree/run.sh create feature-name`
- Use absolute paths when working in worktrees
- Grant permission when prompted (one-time per session)
- Rename temp worktrees: `tools/worktree/run.sh rename new-name`

<!-- TOOLS:END -->
