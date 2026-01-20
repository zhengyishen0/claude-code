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

**Worktree Structure**:
```
~/Codes/.worktrees/<project>/
├── <active-worktrees>/     # e.g., feature-login, fix-bug
└── .archive/
    └── <archived-worktrees>/   # Completed task worktrees
```

**Creating a worktree**:
```bash
# Manual worktrees (human-driven)
git worktree add -b feature-name ~/Codes/.worktrees/claude-code/feature-name

# Task agent worktrees (auto-created by world spawn)
# Location: ~/Codes/.worktrees/<project>/<task-id>/
```

**Using the worktree**:
Use absolute paths when working in worktrees:
```bash
# Good: absolute paths
~/Codes/.worktrees/claude-code/feature-name/src/file.js

# Avoid: cd and relative paths
cd ~/Codes/.worktrees/... && edit src/file.js
```

**Cleanup after merge**:
```bash
git merge feature-name
git worktree remove ~/Codes/.worktrees/claude-code/feature-name
git branch -d feature-name
```

**Task Worktree Archival**:
When tasks are verified/canceled, worktrees are archived (not deleted):
```bash
# Archived to: ~/Codes/.worktrees/<project>/.archive/<task-id>-<timestamp>/
# Can be restored with: supervisor retry <task-id>
```

**MANDATORY**: Every Claude session MUST create a dedicated worktree before making ANY changes, no matter how small. No exceptions for typos, docs, or single-line fixes.

**Main Branch Protection**: A PreToolUse hook blocks Edit/Write/commit on main branch. You must create a worktree first.

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

**Root-level tools** (direct aliases): `browser`, `browser-js`, `memory`, `world`

**tools/** (remaining): `screenshot`, `proxy`

### browser
Browser automation with React/SPA support + Vision-based automation (CDP)

Run `browser` for full help. Alternative: `browser-js` (Node.js rewrite, same features).

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

**Commands:** create, check, supervisor

**Create Examples:**
```bash
# Events (facts)
world create --event "git:commit" "fix: login bug"
world create --event "system" --session abc123 "task started"

# Tasks (to-dos with lifecycle)
world create --task "login-fix" "pending" "now" "Fix login" --need "tests pass"
world create --task "login-fix" "running"
world create --task "login-fix" "done"

# Agent status (shorthand)
world create --agent start abc123 "Starting task"
world create --agent finish abc123 "Task completed"
```

**Check Examples:**
```bash
world check                           # All entries
world check --task --status pending   # Pending tasks
world check --session abc123          # Filter by session
```

**Key Principles:**
1. **Two commands** - `create` and `check` only
2. **Two data types** - Events (facts) and Tasks (to-dos)
3. **Plain text** - Human readable, grep-able with `rg`
4. **Append-only** - Never delete, only add
5. **Unified format** - `|` separators for parsing

### memory
Cross-session knowledge sharing for Claude Code - search and consult previous sessions like a hive mind.

Run `memory` for full help.

**Commands:** search

**Workflow:**
1. `memory search "keywords"` - Search first
2. If snippets answer your question, you're done
3. If you need more detail: `memory search "refined keywords" --recall "question"`

**Example:**
```bash
# Broad search
memory search "browser automation"

# Refined search (if needed)
memory search "browser click"
# → If snippets answer your question, stop here!

# Only use --recall when snippets aren't enough
memory search "browser click" --recall "how to click by text?"
```

**Key Principles:**
1. **Search First** - Snippets often contain enough information
2. **Recall is Optional** - Only use when snippets aren't sufficient
3. **Refine Before Recall** - Good keywords = good recall results
4. **Cross-Project** - Sessions from any project can be searched

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

<!-- TOOLS:END -->
