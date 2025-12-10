# Claude Code Project

## Project Setup

**First-time setup**: Run `claude-tools init` to install all prerequisites via Brewfile.

```bash
claude-tools init
```

This command:
- Checks if Homebrew is installed
- Runs `brew bundle install` to install missing dependencies
- Shows installed versions of all tools
- Generates/updates `Brewfile.lock.json` for reproducibility

**Dependencies managed via Brewfile:**
- `git` - Version control
- `node@18` - Node.js 18.x runtime
- `chrome-cli` - Browser automation CLI
- `claude` - Claude Code CLI tool

**Version locking:**
- `Brewfile` defines dependencies with version constraints (e.g., `node@18`)
- `Brewfile.lock.json` pins exact versions for reproducibility
- Commit both files to ensure consistent environments

**Manual Brewfile operations:**
```bash
brew bundle check              # Check if all dependencies installed
brew bundle install            # Install missing dependencies
brew bundle install --upgrade  # Update all dependencies & lockfile
```

**After running init**, use `claude-tools sync` to update CLAUDE.md with tool documentation.

## Development Workflow

**Default**: Use git worktrees for all code changes to maintain branch isolation.

Before making edits:
1. **Check current branch**: `git branch --show-current`
2. **If on `main`**: Run `claude-tools worktree create feature-name`
3. **Work in worktree**: Use absolute paths to make changes
4. **Merge when done**: Merge back to main and remove worktree

**Creating a worktree with Claude**:
```bash
claude-tools worktree create feature-name
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
claude-tools worktree remove feature-name
```

**Exception**: Skip worktrees for trivial changes (typos, docs, single-line fixes).

**Automatic Triggering**: When a user requests feature work and you're on main branch, proactively suggest and run `claude-tools worktree create <feature-name>`.

## Tool Design Principles

When creating tools:
1. **Self-documenting** - Tools document themselves via `help` command
2. **Help as default** - Running with no args shows help
3. **README-based docs** - Full documentation in README.md (used by `claude-tools sync`)
4. **Standard entry point** - Each tool uses `run.sh`, name derived from folder
5. **Add to Brewfile** - If tool needs system dependencies, add to Brewfile

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
```

**Adding dependencies:**
If your tool needs system packages, add them to the root `Brewfile`:
```ruby
# In Brewfile
brew "new-dependency"           # Latest version
brew "versioned-dep@14"        # Specific major version
```

## Command Execution Guidelines

Avoid wrapping tool commands in bash variables - use direct tool entry points instead.

**Bad** (triggers permission prompts):
```bash
JS_CODE=$(cat claude-tools/chrome/js/click-element.js) && chrome-cli execute '...'
```

**Good** (pre-approved):
```bash
claude-tools chrome click "[Homes]"
chrome-cli execute 'document.querySelector("button").click()'
```

## Available Tools

<!-- TOOLS:AUTO-GENERATED -->

Universal entry: `claude-tools <tool> [command] [args...]`

### chrome
Browser automation with React/SPA support

Run `claude-tools chrome` for full help.

**Commands:** snapshot, inspect, open, wait, click, input, esc

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

Run `claude-tools playwright` for full help.

**Commands:** open, recon, click, input, wait, close

### screenshot
Background window capture for macOS with automatic dual-version output

Run `claude-tools screenshot` for full help.

**Commands:** `<app_name|window_id> [output_path]`, `--list`

**Key Principles:**
1. **No activation required** - Captures windows in the background using macOS CGWindowID
2. **Dual-output always** - Always saves both downscaled (AI-optimized) and full-res versions
3. **AI-first workflow** - Downscaled version is default for analysis, full version available when needed
4. **No decisions needed** - Simple interface with no flags or options
5. **Project-local storage** - Screenshots saved to `./tmp/` by default

### worktree
Git worktree management with automatic Claude session launching.

Run `claude-tools worktree` for full help.

<!-- TOOLS:END -->
