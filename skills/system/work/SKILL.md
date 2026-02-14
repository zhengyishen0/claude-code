---
name: work
description: Agent workspace management with jj (NOT git).
---

# work

Agent workspace management using jj workspaces.

## Usage

```bash
# Start work — ALWAYS use cd "$(...)"; workspace path is persistent
cd "$(work on 'task description')"

# Stack another task on current work
cd "$(work on 'another task')"

# Finish work (merges to main)
work done "summary"

# Clean up
work clean          # dry run — show what would be cleaned
work clean --safe   # clean empty orphans (no workspace @)
work clean --space  # clean empty workspace leftovers

# Push
jj git push
```

> **IMPORTANT**: Always use `cd "$(work on ...)"` — the command outputs the workspace path.
> Never do `cd ~/.workspace/xxx && work on` — this breaks the workflow.

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

### `work clean [--safe | --space]`

1. No args: dry run — shows what would be cleaned
2. `--safe`: cleans empty orphan leaves (no workspace @)
3. `--space`: cleans empty workspace leftovers, moves workspaces to main
4. Never touches [PROTECTED] (default@ safety buffer)

## jj Quick Reference

| Task | git | jj |
|------|-----|-----|
| Status | `git status` | `jj status` |
| Diff | `git diff` | `jj diff` |
| Log | `git log` | `jj log` |
| Commit | `git add && git commit` | `jj new -m "msg"` |
| Amend | `git commit --amend` | `jj describe -m "msg"` |
| Push | `git push` | `work clean && jj git push` |

### Critical Difference

```bash
jj describe -m "msg"     # Update CURRENT commit (changes stay here)
jj new -m "msg"          # Create NEW commit (changes stay in parent)
```

## Working with Submodules

Community skills are git submodules with their own jj tracking.

**Edit submodule directly (no workspace needed):**
```bash
cd skills/community/<skill>     # Has its own jj
jj new                          # Work commit in submodule
# ... make changes ...
jj commit -m "description"
jj git push                     # Push to skill's remote
```

**Update submodule pointer (workspace needed):**
```bash
cd "$(work on 'bump skill')"    # Workspace in parent
cd skills/community/<skill>
git pull origin master
cd ../..                        # Back to workspace root
work done "bump <skill>"        # Commits new pointer
```

| Task | Where to work |
|------|---------------|
| Edit submodule code | `cd skills/community/<skill>/` (its own jj) |
| Add/remove submodule | Parent workspace (`work on`) |
| Update submodule pointer | Parent workspace (`work on`) |

## Rules for AI

1. **Always `cd "$(work on ...)"` before editing** — this creates workspace AND changes directory
2. **Never `cd ~/.workspace/... && work on`** — this breaks the workflow
3. **One workspace per session** — `~/.workspace/[session-id]`, path is persistent
4. **Stack with `cd "$(work on ...)"` again** — creates child commit
5. **Finish with `work done`** — merges to main, keeps workspace at main
6. **Never `jj abandon`** — escalate to user instead
7. **Submodule edits don't need workspace** — cd into submodule, use its jj
