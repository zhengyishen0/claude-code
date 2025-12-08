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

    # Create worktree
    local worktree_path="../claude-code-$branch_name"
    git worktree add -b "$branch_name" "$worktree_path"

    if [ $? -ne 0 ]; then
        echo "Failed to create worktree"
        exit 1
    fi

    # Resolve absolute path
    local abs_path="$(cd "$worktree_path" && pwd)"

    echo "Created worktree: $abs_path"

    # Launch new terminal with Claude
    launch_terminal "$abs_path"

    # Exit current session
    echo "Exiting current session..."
    exit 0
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

# Launch new terminal based on OS
launch_terminal() {
    local target_path="$1"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: Try iTerm2 first, fall back to Terminal.app
        if pgrep -q "iTerm2" 2>/dev/null; then
            osascript -e 'tell application "iTerm2" to create window with default profile command "cd '"$target_path"' && claude --fork-session"'
        else
            osascript -e 'tell application "Terminal" to do script "cd '"$target_path"' && claude --fork-session"'
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux: Try common terminals
        if command -v gnome-terminal &> /dev/null; then
            gnome-terminal -- bash -c "cd '$target_path' && claude --fork-session"
        elif command -v xfce4-terminal &> /dev/null; then
            xfce4-terminal --command="bash -c 'cd $target_path && claude --fork-session'"
        else
            echo "Warning: Could not auto-launch terminal"
            echo "Run manually: cd $target_path && claude --fork-session"
        fi
    else
        echo "Warning: Unsupported OS for auto-launch"
        echo "Run manually: cd $target_path && claude --fork-session"
    fi
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
  2. Work in new Claude session (auto-launched)
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
