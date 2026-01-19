# Supervisor System Implementation Report

## Overview

Implemented a standalone `supervisor` tool that orchestrates task agents by spawning them in dedicated git worktrees.

## Changes Made

### New Files

#### `supervisor/run.sh` - Main Entry Point
- Commands: `spawn <task-id>`, `level1 [run|list]`, `once`
- Shows help when called with no arguments
- Routes to sub-commands

#### `supervisor/spawn_task.sh` - Task Spawner
- Reads task info from `world.log`
- Creates git worktree: `../claude-code-task-<id>`
- Sets environment variables:
  - `AGENT_TYPE=task`
  - `AGENT_SESSION_ID=<task-id>`
  - `AGENT_DESCRIPTION=<description>`
  - `CLAUDE_PROJECT_DIR=<worktree-path>`
- Updates task status to `running`
- Starts claude with `--print --cwd <worktree-path>`

#### `supervisor/level1.sh` - Level 1 Supervisor
- Reads pending tasks from `world.log`
- Checks trigger conditions (currently only `now` implemented)
- Spawns tasks that are ready (not already running)
- Supports `DRY_RUN=true` for testing
- Commands: `run` (default), `list`

### Modified Files

#### `world/run.sh`
- Removed `supervisor|supervisors` routing
- Updated help text to indicate supervisor is now a separate tool
- Removed `SUPERVISORS_DIR` variable

### Root-Level Symlink

- `supervisor -> supervisor/run.sh` (for easy access)

## Usage Examples

```bash
# Show help
supervisor

# Create a pending task
world create --task login-fix pending now "Fix login bug" --need "tests pass"

# Manually spawn a task
supervisor spawn login-fix

# List pending tasks
supervisor level1 list

# Auto-trigger pending tasks
supervisor level1

# Run all levels once
supervisor once

# Dry run mode
DRY_RUN=true supervisor once
```

## Architecture

```
supervisor/
├── run.sh          # Main entry point
├── spawn_task.sh   # Create worktree + start claude
└── level1.sh       # Trigger pending tasks

Each spawned task runs in its own worktree:
../claude-code-task-<id>/
```

## Future Work

- Level 2 supervisor for task verification
- Additional trigger types: `<datetime>`, `after:<task-id>`
- Task dependency management
- Parallel task execution limits
