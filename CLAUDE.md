# Claude Code Project

## Project Setup

**Dependencies** are managed via Homebrew Brewfile:
- `git` - Version control
- `node@18` - Node.js 18.x runtime
- `chrome-cli` - Browser automation CLI
- `claude` - Claude Code CLI tool

**Manual Brewfile operations:**
```bash
brew bundle check              # Check if all dependencies installed
brew bundle install            # Install missing dependencies
brew bundle install --upgrade  # Update all dependencies & lockfile
```

## Development Workflow

**Default**: Use git worktrees for all code changes to maintain branch isolation.

**Before ANY edit**:
1. Check current branch: `git branch --show-current`
2. If on `main`: Create a worktree first
3. Make changes ONLY in the worktree using absolute paths

**After EACH edit**:
- Stage the change immediately: `git add <file>`

**Creating a worktree with Claude**:
```bash
worktree create feature-name
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
worktree remove feature-name
```

**MANDATORY**: Every Claude session MUST create a dedicated worktree before making ANY changes, no matter how small. No exceptions for typos, docs, or single-line fixes.

**Automatic Triggering**: When on main branch and ANY edit is needed, immediately run `worktree create <feature-name>` before making changes.

## Tool Design Principles

When creating tools:
1. **No args = help** - Running a tool without arguments MUST show help
2. **README-based docs** - Full documentation in README.md
3. **Standard entry point** - Each tool uses `run.sh`, name derived from folder
4. **Add to Brewfile** - If tool needs system dependencies, add to Brewfile

**Help convention:**
```bash
# Correct - no args shows help
browser           # Shows help
memory            # Shows help
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
JS_CODE=$(cat browser/js/click-element.js) && chrome-cli execute '...'
```

**Good** (pre-approved):
```bash
browser click "[Homes]"
chrome-cli execute 'document.querySelector("button").click()'
```

## Available Tools

<!-- TOOLS:AUTO-GENERATED -->

**Root-level tools** (direct aliases): `browser`, `memory`, `world`, `worktree`

**tools/** (remaining): `screenshot`, `proxy`

### browser
Browser automation with React/SPA support + Vision-based automation (CDP)

Run `browser` for full help.

**Commands:** snapshot, inspect, open, wait, click, input, hover, drag, sendkey, tabs, execute, screenshot, profile

**Key Principles (in order of preference):**
1. **URL params first (PREFERRED)** - Always construct URLs for search/filter (10x faster than clicking)
2. **Selectors second** - Use CSS selectors or text when URL construction not possible
3. **Vision last resort** - Use screenshot + coordinates ONLY when selectors don't work
4. **Auto-feedback shows results** - All interaction commands automatically show what changed
5. **Trust the tool** - Commands wait for stability before showing results

### world
Single source of truth for agent coordination

Run `world` for full help.

**Commands:** event, agent, check, query, respond, supervisor

**Key Principles:**
1. **Plain text** - Human readable, grep-able with `rg`
2. **Append-only** - Never delete, only add
3. **Two types** - Events (facts) and Agents (tracked projects)
4. **Marker-based reading** - Only see new entries after last check
5. **| need:** - Success criteria (start) or blocker requirement (failed)
6. **Two-level supervision** - Level 1 (state enforcement) and Level 2 (AI verification)

### memory
Cross-session knowledge sharing for Claude Code - search and consult previous sessions like a hive mind.

Run `memory` for full help.

**Commands:** search, recall

**Search Syntax (two modes, auto-detected by presence of pipes):**

- **Simple mode** (recommended): `"browser automation workflow"` → OR all keywords, rank by hits
- **Strict mode** (advanced): `"browser|chrome automation"` → (browser OR chrome) AND automation

**When to use each:**
- Simple: Exploratory searches, finding related topics - just list keywords
- Strict: Need specific term combinations - use pipes for AND/OR logic

**Key Principles:**
1. **Simple by Default** - Just list keywords, sessions matching more rank higher
2. **Smart Ranking** - Keyword hits → match count → recency (soft AND effect)
3. **Backward Compatible** - Pipes trigger strict AND/OR mode for power users
4. **Incremental Indexing** - Full index on first run (~12s), incremental updates after (~0.5s)
5. **Clean Output** - Filters noise (tool results, IDE events, system messages)
6. **Fresh Fork by Default** - Each recall creates a fresh fork; use `--resume` for follow-ups
7. **Cross-Project Recall** - Sessions from any project can be recalled

### proxy
Automatically enable HTTP/HTTPS proxy when VPN is connected - no manual toggling needed!

Run `proxy` for full help.

**Commands:** check, status, enable, disable, init, config

**Key Principles:**
1. **Zero overhead when disconnected** - Fast port check (~10ms) doesn't slow down terminal startup
2. **Automatic activation** - Works for every new terminal instance without manual intervention
3. **VPN-aware** - Only enables when proxy is actually reachable
4. **Project-local config** - Configuration stored in repo, can be gitignored or shared with team
5. **Manual override available** - Use `enable`/`disable` commands for one-off changes

### screenshot
Background window capture for macOS with automatic dual-version output

Run `screenshot` for full help.

**Commands:** `<app_name|window_id> [output_path]`, `--list`

**Key Principles:**
1. **No activation required** - Captures windows in the background using macOS CGWindowID
2. **Dual-output always** - Always saves both downscaled (AI-optimized) and full-res versions
3. **AI-first workflow** - Downscaled version is default for analysis, full version available when needed
4. **No decisions needed** - Simple interface with no flags or options
5. **Project-local storage** - Screenshots saved to `./tmp/` by default

### worktree
Git worktree management with automatic Claude session launching.

Run `worktree` for full help.

<!-- TOOLS:END -->
