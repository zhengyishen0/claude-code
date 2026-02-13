---
name: work
description: Agent workspace management with jj (NOT git).
---

# work

Agent workspace management using jj workspaces.

## Usage

```bash
# Start work (creates isolated workspace, cd is persistent)
cd "$(work on 'task description')"

# Finish work (merges to main, cleans up)
work done "summary"

# Abandon work (removes workspace, change becomes orphaned)
work drop

# Clean up empty leaf orphans
work clean      # interactive
work clean -y   # auto-confirm (for scripts/agents)

# Push to remote (checks for orphans first)
work push
```

## Example

```bash
cd "$(work on 'fix login bug')"
# task: fix login bug
# cwd:  /Users/.../.workspace/[3a880298] (persistent)

# ... do work ...

work done "fixed login validation"
# or: work drop  (if abandoning)
```

## What Happens

### `work on "task"`

1. Gets session ID from `$CLAUDE_SESSION_ID` (first 8 chars)
2. Creates jj workspace at `~/.workspace/[session-id]`
3. Saves repo root to `.repo_root` file
4. Creates new commit off main: `[session-id] task`
5. Outputs path for `cd` (info goes to stderr)

### `work done "summary"`

1. Gets change ID from workspace
2. Reads repo root from `.repo_root`
3. Creates merge commit on main
4. Forgets workspace and deletes directory

### `work drop`

1. Forgets workspace (change becomes orphaned, not abandoned)
2. Deletes workspace directory
3. No merge - change stays in repo but disconnected (will be GC'd)

### `work clean [-y]`

1. Finds empty leaf orphans: `heads(all()) & empty() & ~::bookmarks()`
2. Shows commits and prompts for confirmation (skip with `-y`)
3. Abandons them if confirmed

### `work push`

1. Checks for all orphan commits
2. If empty leaf orphans: suggests `work clean -y`
3. If other orphans: suggests manual cleanup, aborts
4. If clean: runs `jj git push`

## jj Quick Reference

| Task | git | jj |
|------|-----|-----|
| Status | `git status` | `jj status` |
| Diff | `git diff` | `jj diff` |
| Log | `git log` | `jj log` |
| Commit | `git add && git commit` | `jj new -m "msg"` |
| Amend | `git commit --amend` | `jj describe -m "msg"` |
| Push | `git push` | `work push` |

### Critical Difference

```bash
jj describe -m "msg"     # Update CURRENT commit (changes stay here)
jj new -m "msg"          # Create NEW commit (changes stay in parent)
```

## Rules for AI

1. **Always `work on` before editing** - creates isolated workspace
2. **One workspace per session** - `~/.workspace/[session-id]`
3. **Tag commits with session ID** - `jj new -m "[session-id] description"`
4. **Finish before starting new work** - one task at a time
5. **Never `jj abandon`** - escalate to user instead
