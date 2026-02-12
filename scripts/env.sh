#!/usr/bin/env bash
# env.sh - Source this in ~/.zshrc:
#   source ~/.claude-code/scripts/env.sh

# ============================================================
# Colors (for scripts that source this)
# ============================================================
_GREEN='\033[0;32m'
_YELLOW='\033[0;33m'
_RED='\033[0;31m'
_NC='\033[0m'

ok()   { echo -e "${_GREEN}✓${_NC} $1"; }
warn() { echo -e "${_YELLOW}!${_NC} $1"; }
err()  { echo -e "${_RED}✗${_NC} $1"; }

# ============================================================
# Auto-discover skills (creates aliases for skills/*/run)
# ============================================================
for _skill in ~/.claude-code/skills/*/run; do
    [[ -x "$_skill" ]] || continue
    _name=$(basename "$(dirname "$_skill")")
    alias $_name="$_skill"
done
unset _skill _name

# ============================================================
# cc - Claude Code wrapper
# ============================================================
# Usage:
#   cc                    Start new session
#   cc -r <partial>       Resume session by partial ID
#   cc <args>             Pass through to claude

cc() {
    if [[ "${1:-}" == "-r" || "${1:-}" == "--resume" ]]; then
        local partial="${2:-}"
        if [[ -z "$partial" ]]; then
            echo "Usage: cc -r <partial-session-id>" >&2
            echo "" >&2
            ~/.claude-code/skills/session/run list 5
            return 1
        fi

        local session_id
        session_id=$(~/.claude-code/skills/session/run find "$partial") || return 1
        echo "Resuming: $session_id" >&2
        shift 2
        command claude --resume "$session_id" "$@" --dangerously-skip-permissions  
    else
        command claude "$@" --dangerously-skip-permissions  
    fi
}

# ============================================================
# Claude CLI aliases
# ============================================================
alias claude-ps='pgrep -fl "^claude"'
alias claude-kill='pkill -9 "^claude"'

# ============================================================
# Auto-init: Enable proxy if reachable
# ============================================================
eval "$(~/.claude-code/skills/proxy/run init 2>/dev/null)"

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
