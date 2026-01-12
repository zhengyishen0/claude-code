# Worktree Tool

Git worktree management for isolated feature development.

## Quick Start

```bash
# Create worktree
worktree create feature-name

# List all worktrees
worktree list

# Remove a worktree
worktree remove feature-name
```

## Full Documentation

Run `worktree` for complete documentation.

## How It Works

1. Creates a git worktree at `../claude-code-<branch-name>`
2. Creates a new branch with the same name
3. Returns absolute path for use with Claude Code

This allows you to work on features in isolation while keeping main branch clean.
