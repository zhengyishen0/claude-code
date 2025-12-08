# Claude Code Project

## Development Workflow

**Default**: Use git worktrees for all code changes to maintain branch isolation.

Before making edits:
1. **Check current branch**: `git branch --show-current`
2. **If on `main`**: Create a new worktree for the feature
3. **Work in worktree**: Make all changes there
4. **Merge when done**: Merge back to main and remove worktree

**Creating a worktree**:
```bash
git worktree add -b feature-name ../claude-code-feature
cd ../claude-code-feature
```

**Cleanup after merge**:
```bash
cd ../claude-code
git merge feature-name
git worktree remove ../claude-code-feature
```

**Exception**: Skip worktrees for trivial changes (typos, docs, single-line fixes).

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

**Commands:** recon, open, wait, click, input, esc, tabs, info, close, help

**Key Principles:**
1. URL params first - always prefer direct URLs over clicking
2. Use chrome tool commands - avoid chrome-cli execute unless truly needed
3. Recon first - understand page before interacting
4. Chain with + - action + wait + recon in one call
5. Wait for specific element - not just any DOM change
6. Use --gone when expecting element to disappear
7. Filter recon with grep/awk - `recon | awk '/^## Main($|:)/,/^## [^M]/'`

<!-- TOOLS:END -->
