#!/usr/bin/env bash
# worktree.sh - Manage git worktrees
set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

PROJECT_WORKTREES="$(dirname "$PROJECT_DIR")/.worktrees/$(basename "$PROJECT_DIR")"
PROJECT_ARCHIVE="$PROJECT_WORKTREES/.archive"

show_help() {
    cat <<'HELP'
Usage: worktree [command] [name]

Commands:
  (default)      List worktrees with status
  create <name>  Create new worktree and branch
  merge <name>   Merge to main, archive worktree
  abandon <name> Archive worktree without merging
HELP
}

do_list() {
    local worktrees
    worktrees=$(git -C "$PROJECT_DIR" worktree list --porcelain | grep "^worktree " | sed 's/worktree //')

    echo "Worktrees:"
    echo ""

    while IFS= read -r path; do
        # Skip main project directory
        if [ "$path" = "$PROJECT_DIR" ]; then
            continue
        fi

        local name=$(basename "$path")
        local status=""

        # Check for uncommitted changes
        if [ -d "$path" ]; then
            local changes=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
            if [ "$changes" -gt 0 ]; then
                status=" ($changes uncommitted)"
            else
                status=" (clean)"
            fi
        else
            status=" (missing)"
        fi

        echo "  $name$status"
        echo "    $path"
    done <<< "$worktrees"

    # Check for orphan branches (branches without worktrees)
    local worktree_branches=$(git -C "$PROJECT_DIR" worktree list | awk '{print $NF}' | tr -d '[]')
    local all_branches=$(git -C "$PROJECT_DIR" branch --format='%(refname:short)' | grep -v '^main$' | grep -v '^master$')

    local orphans=""
    for branch in $all_branches; do
        if ! echo "$worktree_branches" | grep -q "^$branch$"; then
            orphans="$orphans $branch"
        fi
    done

    if [ -n "$orphans" ]; then
        echo ""
        echo "Orphan branches (no worktree):"
        for branch in $orphans; do
            echo "  $branch"
        done
    fi
}

do_create() {
    local name="$1"
    local worktree_path="$PROJECT_WORKTREES/$name"

    if [ -d "$worktree_path" ]; then
        echo "Error: Worktree already exists: $worktree_path" >&2
        exit 1
    fi

    mkdir -p "$PROJECT_WORKTREES"

    echo "Creating worktree: $worktree_path"
    git -C "$PROJECT_DIR" worktree add -b "$name" "$worktree_path"

    echo ""
    echo "Worktree created:"
    echo "  Path:   $worktree_path"
    echo "  Branch: $name"
}

do_archive() {
    local name="$1"
    local worktree_path="$PROJECT_WORKTREES/$name"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local archive_path="$PROJECT_ARCHIVE/${name}-${timestamp}"

    mkdir -p "$PROJECT_ARCHIVE"

    # Move worktree to archive
    if [ -d "$worktree_path" ]; then
        mv "$worktree_path" "$archive_path"
        echo "  Archived to: $archive_path"
    fi

    # Remove from git worktree list
    git -C "$PROJECT_DIR" worktree prune
}

do_merge() {
    local name="$1"
    local worktree_path="$PROJECT_WORKTREES/$name"

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

    echo "Merging: $name"

    # Merge into main
    echo "  Merging $name..."
    git -C "$PROJECT_DIR" merge "$name"

    # Archive worktree
    do_archive "$name"

    # Delete branch
    echo "  Deleting branch..."
    git -C "$PROJECT_DIR" branch -d "$name"

    echo ""
    echo "Merge complete: $name"
}

do_abandon() {
    local name="$1"
    local worktree_path="$PROJECT_WORKTREES/$name"

    if [ ! -d "$worktree_path" ]; then
        # Check if branch exists without worktree
        if git -C "$PROJECT_DIR" branch --list "$name" | grep -q "$name"; then
            echo "Abandoning orphan branch: $name"
            git -C "$PROJECT_DIR" branch -D "$name"
            echo "Branch deleted: $name"
            return
        fi
        echo "Error: Worktree not found: $worktree_path" >&2
        exit 1
    fi

    echo "Abandoning: $name"

    # Archive worktree (keeps the files)
    do_archive "$name"

    # Force delete branch
    echo "  Deleting branch..."
    git -C "$PROJECT_DIR" branch -D "$name"

    echo ""
    echo "Abandoned: $name (archived, not merged)"
}

# Parse arguments
case "${1:-}" in
    ""|list)
        do_list
        ;;
    create)
        [ $# -lt 2 ] && { echo "Error: create requires <name>" >&2; exit 1; }
        do_create "$2"
        ;;
    merge)
        [ $# -lt 2 ] && { echo "Error: merge requires <name>" >&2; exit 1; }
        do_merge "$2"
        ;;
    cleanup)
        # Backward compatibility
        [ $# -lt 2 ] && { echo "Error: cleanup requires <name>" >&2; exit 1; }
        do_merge "$2"
        ;;
    abandon)
        [ $# -lt 2 ] && { echo "Error: abandon requires <name>" >&2; exit 1; }
        do_abandon "$2"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: $1" >&2
        show_help >&2
        exit 1
        ;;
esac
