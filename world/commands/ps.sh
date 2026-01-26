#!/usr/bin/env bash
# world/commands/ps.sh
# List running task agents (ZFC observability)

set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

# ZFC: Source process utilities
source "$PROJECT_DIR/utils/process.sh"

TASKS_DIR="$PROJECT_DIR/task/data"

show_help() {
    cat <<'EOF'
ps - List running task agents

USAGE:
    world ps

DESCRIPTION:
    Shows all currently running task agents.
    Uses ZFC (Zero File-based State) - queries process table directly.

OUTPUT:
    TASK                 PID        SESSION                              TITLE
    fix-bug              12345      abc-123-def-456                      Fix login bug
EOF
}

if [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi

echo "=== Running Task Agents ==="
echo ""

# Get running sessions
running=$(list_running_tasks)

if [ -z "$running" ]; then
    echo "No task agents running."
    exit 0
fi

printf "%-20s %-10s %-36s %s\n" "TASK" "PID" "SESSION" "TITLE"
printf "%-20s %-10s %-36s %s\n" "----" "---" "-------" "-----"

echo "$running" | while read -r session_id pid; do
    # Find task MD with this session_id
    task_id=""
    title=""
    for md_file in "$TASKS_DIR"/*.md; do
        [ -e "$md_file" ] || continue
        md_session=$(yq eval --front-matter=extract '.session_id' "$md_file" 2>/dev/null || echo "")
        if [ "$md_session" = "$session_id" ]; then
            task_id=$(yq eval --front-matter=extract '.id' "$md_file" 2>/dev/null || echo "")
            title=$(yq eval --front-matter=extract '.title' "$md_file" 2>/dev/null || echo "")
            break
        fi
    done

    printf "%-20s %-10s %-36s %s\n" "${task_id:-unknown}" "$pid" "$session_id" "${title:-}"
done
