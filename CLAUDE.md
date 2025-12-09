# Claude Code Project

## Project Setup

**First-time setup**: Run `tools/run.sh init` to check and install all prerequisites.

```bash
tools/run.sh init
```

This command:
- Scans all tool READMEs for prerequisites
- Checks which tools are installed
- Automatically installs missing required tools
- Shows optional tools that could improve performance

**What it checks:**
- System tools: git, node, npm
- Browser automation: chrome-cli, Google Chrome
- Tool-specific: playwright browsers, claude CLI

**After running init**, use `tools/run.sh sync` to update CLAUDE.md with tool documentation.

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
2. **Help as default** - Running with no args shows help
3. **README-based docs** - Full documentation in README.md (used by `tools/run.sh sync`)
4. **Prerequisites in README** - Add `## Prerequisites` section for `tools/run.sh init`
5. **Standard entry point** - Each tool uses `run.sh`, name derived from folder

**README Structure** (required for sync):
```markdown
# Tool Name

Brief one-line description

## Commands

### command1
Description

### command2
Description

## Key Principles (optional)

1. Principle one
2. Principle two

## Prerequisites

- tool (required): brew install tool
- optional-tool (optional): npm install -g optional-tool
```

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

**Commands:** snapshot, open, wait, click, input, esc

**Key Principles:**
1. **URL params first** - Always prefer direct URLs over clicking
2. **Use chrome tool commands** - Avoid `chrome-cli execute` unless truly needed
3. **Snapshot first** - Understand page before interacting
4. **Track changes with --diff** - See what changed after interactions
5. **Chain with +** - Combine action + wait + snapshot in one call
6. **Wait for specific element** - Not just any DOM change
7. **Use --gone** - When expecting element to disappear
8. **Use --network for lazy content** - Wait for footer/ads to load

### playwright
Cross-platform browser automation with Playwright, wrapped in a shell-friendly CLI similar to the chrome tool.

Run `tools/playwright/run.sh` for full help.

**Commands:** open, recon, click, input, wait, close

### worktree
Git worktree management with automatic Claude session launching.

Run `tools/worktree/run.sh` for full help.

<!-- TOOLS:END -->
