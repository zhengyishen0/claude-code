#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"

# Subcommand: create
worktree_create() {
    local branch_name="$1"

    # Validate branch name
    if [ -z "$branch_name" ]; then
        echo "Error: Branch name required"
        exit 1
    fi

    # Try to create worktree
    local worktree_path="../claude-code-$branch_name"
    git worktree add -b "$branch_name" "$worktree_path" 2>/dev/null

    if [ $? -ne 0 ]; then
        # Check if worktree already exists
        if [ -d "$worktree_path" ]; then
            echo "Worktree already exists"
        else
            echo "Failed to create worktree"
            exit 1
        fi
    else
        echo "Created worktree"
    fi

    # Resolve absolute path
    local abs_path="$(cd "$worktree_path" && pwd)"

    echo "Worktree ready: $abs_path"
    echo "Use absolute paths, do not cd into the worktree directly."
}

# Subcommand: list
worktree_list() {
    git worktree list
}

# Subcommand: remove
worktree_remove() {
    local branch_name="$1"

    if [ -z "$branch_name" ]; then
        echo "Error: Branch name required"
        exit 1
    fi

    local worktree_path="../claude-code-$branch_name"
    git worktree remove "$worktree_path"
}

# Subcommand: rename
worktree_rename() {
    local new_name="$1"

    if [ -z "$new_name" ]; then
        echo "Error: New name required"
        exit 1
    fi

    local current_branch=$(git branch --show-current)

    # Must be in a temp worktree
    if [[ ! "$current_branch" == temp-* ]]; then
        echo "Error: Not in a temp worktree (current branch: $current_branch)"
        exit 1
    fi

    # Rename branch
    git branch -m "$new_name"

    # Rename worktree directory
    local old_path=$(git rev-parse --show-toplevel)
    local new_path="${old_path%/*}/claude-code-$new_name"

    cd ..
    mv "$old_path" "$new_path"
    cd "$new_path"

    echo "Renamed to: $new_name"
    echo "New path: $new_path"
}

# Show help
show_help() {
    cat <<EOF
Git Worktree Tool for Claude Code
==================================

Manage git worktrees with automatic permissions and temp worktree support.

USAGE:
  worktree <command> [args...]

COMMANDS:
  create <branch-name>  Create worktree and grant permissions
  rename <new-name>     Rename temp worktree to meaningful name
  list                  List all worktrees
  remove <branch-name>  Remove a worktree
  (no args)             Show this help

PREREQUISITES:
EOF

    # Check prerequisites
    if command -v git &> /dev/null; then
        echo "  ✓ git"
    else
        echo "  ✗ git (install: https://git-scm.com/)"
    fi

    if command -v claude &> /dev/null; then
        echo "  ✓ claude CLI"
    else
        echo "  ✗ claude CLI (install: https://claude.com/claude-code)"
    fi

    cat <<EOF

EXAMPLES:
  worktree create feature-auth
  worktree rename my-feature
  worktree list
  worktree remove feature-auth

WORKFLOW:
  1. Create worktree: worktree create my-feature
  2. Use absolute paths: /path/to/claude-code-my-feature/file.js
  3. Complete feature, commit changes
  4. Merge to main: git merge my-feature
  5. Remove worktree: worktree remove my-feature
EOF
}

# Main command router
main() {
    local command="$1"
    shift

    case "$command" in
        create)
            worktree_create "$@"
            ;;
        list)
            worktree_list
            ;;
        remove)
            worktree_remove "$@"
            ;;
        rename)
            worktree_rename "$@"
            ;;
        "")
            show_help
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'worktree' for usage"
            exit 1
            ;;
    esac
}

main "$@"
