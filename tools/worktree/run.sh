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
            local abs_path="$(cd "$worktree_path" && pwd)"
            echo "Worktree already exists: $abs_path"
            echo "Switching to existing worktree..."
            cd "$abs_path"
            exec claude --continue --fork-session
        else
            echo "Failed to create worktree"
            exit 1
        fi
    fi

    # Resolve absolute path
    local abs_path="$(cd "$worktree_path" && pwd)"

    echo "Created worktree: $abs_path"
    echo "Switching to new Claude session..."

    # Change to worktree and exec new Claude session
    # exec replaces current process, automatically closing this session
    cd "$abs_path"
    exec claude --continue --fork-session
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

# Show help
show_help() {
    cat <<EOF
Git Worktree Tool for Claude Code
==================================

Creates isolated git worktrees and launches new Claude sessions.

USAGE:
  tools/worktree/run.sh <command> [args...]

COMMANDS:
  create <branch-name>  Create worktree and launch Claude session
  list                  List all worktrees
  remove <branch-name>  Remove a worktree
  help                  Show this help

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
  tools/worktree/run.sh create feature-auth
  tools/worktree/run.sh list
  tools/worktree/run.sh remove feature-auth

WORKFLOW:
  1. Create worktree: tools/worktree/run.sh create my-feature
  2. Claude switches to new session in same terminal
  3. Complete feature, commit changes
  4. Merge to main: git merge my-feature
  5. Remove worktree: tools/worktree/run.sh remove my-feature
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
        help|--help|-h|"")
            show_help
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'tools/worktree/run.sh help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
