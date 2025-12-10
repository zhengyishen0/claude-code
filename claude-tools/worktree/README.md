# Worktree Tool

Git worktree management with automatic Claude session launching.

## Quick Start

```bash
# Create worktree and launch new Claude session
claude-tools worktree create feature-name

# List all worktrees
claude-tools worktree list

# Remove a worktree
claude-tools worktree remove feature-name
```

## Full Documentation

Run `claude-tools worktree` or `claude-tools worktree help` for complete documentation.

## How It Works

1. Creates a git worktree at `../claude-code-<branch-name>`
2. Launches a new Claude session in the worktree using `--fork-session` to continue conversation context
3. Automatically closes the current session

This allows you to work on features in isolation without permission issues, while maintaining conversation continuity.
