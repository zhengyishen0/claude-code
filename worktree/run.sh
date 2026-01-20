#!/usr/bin/env bash
# worktree/run.sh - Manage git worktrees
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR_DEFAULT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use env vars from shell-init.sh, fallback to script-relative paths
: "${PROJECT_DIR:=$PROJECT_DIR_DEFAULT}"
: "${PROJECT_WORKTREES:=$(dirname "$PROJECT_DIR")/.worktrees/$(basename "$PROJECT_DIR")}"
: "${PROJECT_ARCHIVE:=$PROJECT_WORKTREES/.archive}"

show_help() {
    cat <<'HELP'
worktree - Manage git worktrees

USAGE:
    worktree create <name>     Create worktree at ~/.worktrees/<project>/<name>
    worktree cleanup <name>    Merge, remove worktree, delete branch

EXAMPLES:
    worktree create fix-bug
    worktree cleanup fix-bug

PATHS:
    Worktrees: $PROJECT_WORKTREES/<name>
    Archive:   $PROJECT_ARCHIVE/<name>-<timestamp>
HELP
}

do_create() {
    local name="$1"
    local worktree_path="$PROJECT_WORKTREES/$name"

    if [ -d "$worktree_path" ]; then
        echo "Error: Worktree already exists: $worktree_path" >&2
        exit 1
    fi

    # Ensure directory exists
    mkdir -p "$PROJECT_WORKTREES"

    echo "Creating worktree: $worktree_path"
    git -C "$PROJECT_DIR" worktree add -b "$name" "$worktree_path"

    echo ""
    echo "Worktree created:"
    echo "  Path:   $worktree_path"
    echo "  Branch: $name"
}

do_cleanup() {
    local name="$1"
    local worktree_path="$PROJECT_WORKTREES/$name"

    # Check if worktree exists
    if [ ! -d "$worktree_path" ]; then
        echo "Error: Worktree not found: $worktree_path" >&2
        exit 1
    fi

    # Check for uncommitted changes
    if [ -n "$(git -C "$worktree_path" status --porcelain)" ]; then
        echo "Error: Worktree has uncommitted changes" >&2
        echo "  Path: $worktree_path" >&2
        exit 1
    fi

    echo "Cleaning up: $name"

    # Merge into current branch
    echo "  Merging $name..."
    git -C "$PROJECT_DIR" merge "$name"

    # Remove worktree
    echo "  Removing worktree..."
    git -C "$PROJECT_DIR" worktree remove "$worktree_path"

    # Delete branch
    echo "  Deleting branch..."
    git -C "$PROJECT_DIR" branch -d "$name"

    echo ""
    echo "Cleanup complete: $name"
}

# Parse arguments
if [ $# -lt 1 ]; then
    show_help
    exit 0
fi

case "$1" in
    create)
        [ $# -lt 2 ] && { echo "Error: create requires <name>" >&2; exit 1; }
        do_create "$2"
        ;;
    cleanup)
        [ $# -lt 2 ] && { echo "Error: cleanup requires <name>" >&2; exit 1; }
        do_cleanup "$2"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Run 'worktree help' for usage" >&2
        exit 1
        ;;
esac
