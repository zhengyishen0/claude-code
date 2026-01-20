#!/usr/bin/env bash
# paths.sh - Source this file for project paths
# Usage: source "$(git rev-parse --show-toplevel)/paths.sh"

# Get the actual project root (handles worktrees correctly)
_get_project_root() {
    local git_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null)
    
    if [[ "$git_dir" == *".git/worktrees/"* ]]; then
        # We're in a worktree - get main repo path
        git worktree list 2>/dev/null | head -1 | cut -d' ' -f1
    else
        # We're in main repo
        git rev-parse --show-toplevel 2>/dev/null
    fi
}

# Project paths
PROJECT_DIR="$(_get_project_root)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

# Base directory (parent of project, can override via env)
BASE_DIR="${BASE_DIR:-$(dirname "$PROJECT_DIR")}"

# Worktrees
WORKTREES_DIR="$BASE_DIR/.worktrees"
PROJECT_WORKTREES="$WORKTREES_DIR/$PROJECT_NAME"
PROJECT_ARCHIVE="$PROJECT_WORKTREES/.archive"

# Claude data
CLAUDE_DATA_DIR="${CLAUDE_DATA_DIR:-$HOME/.claude}"
CLAUDE_PROJECTS_DIR="$CLAUDE_DATA_DIR/projects"
CLAUDE_TODOS_DIR="$CLAUDE_DATA_DIR/todos"

# Project-specific
TASKS_DIR="$PROJECT_DIR/tasks"
WORLD_LOG="$PROJECT_DIR/world/world.log"

# Runtime
PID_DIR="/tmp/world/pids"
