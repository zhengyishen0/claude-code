#!/usr/bin/env bash
# env.sh - Source this in ~/.zshrc:
#   source ~/.claude-code/scripts/env.sh

# ============================================================
# PATH-based skill access (auto-discovered via link-skills.sh)
# ============================================================
export PATH="$HOME/.claude-code/scripts/bin:$PATH"

# ============================================================
# Claude CLI aliases
# ============================================================
alias claude-ps='pgrep -fl "^claude"'
alias claude-kill='pkill -9 "^claude"'

# ============================================================
# Auto-init: Enable proxy if reachable
# ============================================================
eval "$("$HOME/.claude-code/skills/proxy/run" init 2>/dev/null)"

# ============================================================
# work - Agent workspace management
# ============================================================
# Usage:
#   work on "task"       - Start headless agent with workspace
#   work done "ws"       - Merge workspace to main and cleanup
#
# For everything else, just use jj:
#   jj new -m "note"     - Record progress
#   jj workspace list    - Show workspaces
#   jj workspace forget  - Abandon workspace

work() {
    local cmd="$1"
    shift

    case "$cmd" in
        on)
            _work_on "$@"
            ;;
        done)
            _work_done "$@"
            ;;
        *)
            echo "Usage: work <command> [args]"
            echo ""
            echo "Commands:"
            echo "  on \"task\"       Start headless agent with workspace"
            echo "  done \"ws\"       Merge workspace to main and cleanup"
            echo ""
            echo "For simple operations, use jj directly:"
            echo "  jj new -m \"msg\"        Record progress"
            echo "  jj workspace list       Show workspaces"
            echo "  jj workspace forget ws  Abandon workspace"
            return 1
            ;;
    esac
}

# work on - Start a headless agent with its own workspace
_work_on() {
    local task="$1"
    if [ -z "$task" ]; then
        echo "Usage: work on \"task description\""
        return 1
    fi

    local project_dir="$HOME/.claude-code"
    local sid=$(openssl rand -hex 4)
    local name="$(echo "$task" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | cut -c1-20)-${sid}"
    local path="$project_dir/../.workspaces/claude-code/${name}"

    mkdir -p "$project_dir/../.workspaces/claude-code"

    if ! jj workspace add --name "${name}" "${path}" 2>/dev/null; then
        echo "Failed to create workspace"
        return 1
    fi

    echo "Workspace: ${name}"
    echo "Path: ${path}"
    echo "Session: ${sid}"
    echo ""
    echo "Starting headless agent..."

    (
        cd "${path}" && \
        jj new main -m "${task} (${sid})" && \
        claude -p "${task}

Session ID: ${sid}
Workspace: ${name}

Record progress: jj new -m \"what you did and why (${sid})\"
When done, prefix final commit with: DONE:" \
        --allowedTools "Read,Write,Edit,Bash,Glob,Grep"
    ) &

    echo ""
    echo "Agent started in background."
    echo ""
    echo "Monitor:"
    echo "  jj log                      # See progress"
    echo "  jj workspace list           # See workspaces"
    echo "  memory search '${sid}'      # Recall reasoning"
    echo ""
    echo "When ready:"
    echo "  work done '${name}' 'summary'"
}

# work done - Merge a workspace to main and clean up
_work_done() {
    local ws="$1"
    local summary="${2:-Merge ${ws}}"
    local project_dir="$HOME/.claude-code"

    if [ -z "$ws" ]; then
        echo "Usage: work done \"workspace-name\" [\"summary\"]"
        echo ""
        echo "Active workspaces:"
        jj workspace list
        return 1
    fi

    local ws_path="$project_dir/../.workspaces/claude-code/${ws}"

    if [ ! -d "$ws_path" ]; then
        echo "Workspace not found: $ws_path"
        return 1
    fi

    local change=$(cd "$ws_path" && jj log -r @ --no-graph -T 'change_id.short()')

    if [ -z "$change" ]; then
        echo "Could not find change ID in workspace"
        return 1
    fi

    echo "Merging change ${change} from ${ws}..."

    cd "$project_dir" && \
    jj new main "${change}" -m "${summary}" && \
    jj bookmark set main -r @ && \
    jj workspace forget "${ws}"

    # Clean up workspace directory
    rm -rf "$ws_path" 2>/dev/null

    echo ""
    echo "Merged and cleaned up"
}
