#!/usr/bin/env bash
# setup - Unified installation for zenix

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZENIX_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$ZENIX_ROOT"

source "$ZENIX_DIR/lib/output.sh"

show_help() {
    cat <<'HELP'
setup - Install and configure zenix

USAGE:
    setup                 Show installation status
    setup all             Install everything
    setup deps            Install brew dependencies (fswatch, yq)
    setup shell           Add env.sh to ~/.zshrc
    setup git-hooks       Set core.hooksPath (works in worktrees)
    setup claude-hooks    Symlink .claude/hooks → hooks/claude
    setup daemon          Install world-watch LaunchAgent
    setup uninstall       Remove all installations

COMPONENTS:
    deps          fswatch, yq (via Homebrew)
    shell         source env.sh in ~/.zshrc
    git-hooks     post-commit, post-merge logging
    claude-hooks  session-start, session-end, main-branch-guard
    daemon        world-watch LaunchAgent (background task watcher)
HELP
}

# ============================================================
# Status checks
# ============================================================
check_deps() {
    local missing=0
    command -v fswatch >/dev/null 2>&1 || { missing=1; }
    command -v yq >/dev/null 2>&1 || { missing=$((missing + 1)); }
    [ $missing -eq 0 ]
}

check_shell() {
    grep -q "source.*zenix/env.sh" ~/.zshrc 2>/dev/null
}

check_git_hooks() {
    local hooks_path
    hooks_path=$(git -C "$PROJECT_DIR" config --get core.hooksPath 2>/dev/null || echo "")
    [ "$hooks_path" = "hooks/git" ]
}

check_claude_hooks() {
    # Check if settings.json points to hooks/claude/
    grep -q "hooks/claude/" "$PROJECT_DIR/.claude/settings.json" 2>/dev/null
}

check_daemon() {
    [ -f "$HOME/Library/LaunchAgents/com.claude.world-watch.plist" ]
}

show_status() {
    echo "=== zenix Setup Status ==="
    echo ""

    if check_deps; then
        ok "deps: fswatch, yq installed"
    else
        warn "deps: missing (run: setup deps)"
    fi

    if check_shell; then
        ok "shell: env.sh sourced in ~/.zshrc"
    else
        warn "shell: not configured (run: setup shell)"
    fi

    if check_git_hooks; then
        ok "git-hooks: post-commit, post-merge installed"
    else
        warn "git-hooks: not installed (run: setup git-hooks)"
    fi

    if check_claude_hooks; then
        ok "claude-hooks: symlinked"
    else
        warn "claude-hooks: not symlinked (run: setup claude-hooks)"
    fi

    if check_daemon; then
        ok "daemon: world-watch installed"
    else
        warn "daemon: not installed (run: setup daemon)"
    fi

    echo ""
    echo "Run 'setup all' to install everything."
}

# ============================================================
# Installation commands
# ============================================================
install_deps() {
    echo "Installing dependencies..."

    if ! command -v brew >/dev/null 2>&1; then
        err "Homebrew not installed. Install from https://brew.sh"
        exit 1
    fi

    if ! command -v fswatch >/dev/null 2>&1; then
        echo "  Installing fswatch..."
        brew install fswatch
    else
        ok "fswatch already installed"
    fi

    if ! command -v yq >/dev/null 2>&1; then
        echo "  Installing yq..."
        brew install yq
    else
        ok "yq already installed"
    fi

    ok "Dependencies installed"
}

install_shell() {
    echo "Configuring shell..."

    local source_line="source \"$PROJECT_DIR/env.sh\""

    if grep -q "source.*zenix/env.sh" ~/.zshrc 2>/dev/null; then
        ok "env.sh already in ~/.zshrc"
    else
        echo "" >> ~/.zshrc
        echo "# Claude Code" >> ~/.zshrc
        echo "$source_line" >> ~/.zshrc
        ok "Added env.sh to ~/.zshrc"
        warn "Run 'source ~/.zshrc' or restart terminal"
    fi
}

install_git_hooks() {
    echo "Installing git hooks..."

    # Use absolute path so all worktrees share the same hooks
    git -C "$PROJECT_DIR" config core.hooksPath "$PROJECT_DIR/hooks/git"
    ok "Set core.hooksPath = $PROJECT_DIR/hooks/git"
    ok "Git hooks will work in main repo and all worktrees"
}

install_claude_hooks() {
    echo "Checking Claude hooks configuration..."

    # Claude hooks are configured via .claude/settings.json
    # pointing to hooks/claude/ - no symlinks needed
    if check_claude_hooks; then
        ok "Claude hooks configured in settings.json"
    else
        warn "settings.json may need updating - check hooks/claude/ paths"
    fi
}

install_daemon() {
    echo "Installing daemon..."

    # Use the daemon tool
    export PROJECT_DIR
    "$PROJECT_DIR/daemon/run.sh" world-watch install
}

install_all() {
    echo "=== Installing zenix ==="
    echo ""
    install_deps
    echo ""
    install_shell
    echo ""
    install_git_hooks
    echo ""
    install_claude_hooks
    echo ""
    install_daemon
    echo ""
    echo "=== Installation complete ==="
}

uninstall_all() {
    echo "=== Uninstalling zenix ==="
    echo ""

    # Remove daemon
    if check_daemon; then
        echo "Removing daemon..."
        export PROJECT_DIR
        "$PROJECT_DIR/daemon/run.sh" world-watch uninstall
    fi

    # Remove git hooks
    echo "Removing git hooks..."
    git -C "$PROJECT_DIR" config --unset core.hooksPath 2>/dev/null || true
    ok "Removed core.hooksPath"

    # Remove claude hooks symlink
    if [ -L "$PROJECT_DIR/.claude/hooks" ]; then
        echo "Removing Claude hooks symlink..."
        rm -f "$PROJECT_DIR/.claude/hooks"
        # Restore backup if exists
        if [ -d "$PROJECT_DIR/.claude/hooks.backup" ]; then
            mv "$PROJECT_DIR/.claude/hooks.backup" "$PROJECT_DIR/.claude/hooks"
            ok "Restored .claude/hooks from backup"
        else
            ok "Removed .claude/hooks symlink"
        fi
    fi

    # Note about shell - don't auto-remove
    warn "Shell config not removed. Manually edit ~/.zshrc if needed."

    echo ""
    echo "=== Uninstall complete ==="
}

# ============================================================
# Main
# ============================================================
case "${1:-status}" in
    status|"")
        show_status
        ;;
    all)
        install_all
        ;;
    deps)
        install_deps
        ;;
    shell)
        install_shell
        ;;
    git-hooks)
        install_git_hooks
        ;;
    claude-hooks)
        install_claude_hooks
        ;;
    daemon)
        install_daemon
        ;;
    uninstall)
        uninstall_all
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: $1" >&2
        show_help
        exit 1
        ;;
esac
