# Worktree Tool

Git worktree management with automatic Claude session launching.

## Quick Start

```bash
# Create worktree and launch new Claude session
tools/worktree/run.sh create feature-name

# List all worktrees
tools/worktree/run.sh list

# Remove a worktree
tools/worktree/run.sh remove feature-name
```

## Full Documentation

Run `tools/worktree/run.sh` or `tools/worktree/run.sh help` for complete documentation.

## How It Works

1. Creates a git worktree at `../claude-code-<branch-name>`
2. Launches a new Claude session in the worktree using `--fork-session` to continue conversation context
3. Automatically closes the current session

This allows you to work on features in isolation without permission issues, while maintaining conversation continuity.

## Prerequisites

- git (required): Pre-installed on macOS
- claude (required): brew install anthropics/claude/claude
