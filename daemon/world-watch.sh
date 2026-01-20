#!/usr/bin/env bash
# daemon/world-watch.sh
# Event-driven world task watcher - runs as LaunchAgent

set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

TASKS_DIR="$PROJECT_DIR/world/tasks"
WORLD_LOG="$PROJECT_DIR/world/world.log"
PID_DIR="/tmp/world-watch/pids"
PROJECT_WORKTREES="$(dirname "$PROJECT_DIR")/.worktrees/$(basename "$PROJECT_DIR")"
PROJECT_ARCHIVE="$PROJECT_WORKTREES/.archive"

SPAWN_CMD="$PROJECT_DIR/world/commands/spawn.sh"
LOG_CMD="$PROJECT_DIR/world/commands/log.sh"
DAEMON_LOG="/tmp/world-watch/daemon.log"

mkdir -p "$PID_DIR" "$TASKS_DIR" "$(dirname "$DAEMON_LOG")"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$DAEMON_LOG"
}

show_help() {
    cat <<'EOF'
watch-daemon - Event-driven world daemon using fswatch

USAGE:
    watch-daemon [command]

COMMANDS:
    start       Start watching (foreground, for LaunchAgent)
    once        Run one sync cycle and exit
    help        Show this help

ENVIRONMENT:
    Requires: PROJECT_DIR (source env.sh)

DESCRIPTION:
    Uses fswatch to monitor task files for changes.
    On change: sync → spawn → recover → archive
EOF
}

# ============================================================
# Core functions (from watch.sh)
# ============================================================

sync_to_log() {
    local md_file="$1"
    [ -f "$md_file" ] || return 0

    local id=$(yq eval --front-matter=extract '.id' "$md_file" 2>/dev/null || echo "")
    [ -z "$id" ] && return 0

    local status=$(yq eval --front-matter=extract '.status' "$md_file" 2>/dev/null || echo "pending")
    local title=$(yq eval --front-matter=extract '.title' "$md_file" 2>/dev/null || echo "Untitled")
    local wait=$(yq eval --front-matter=extract '.wait // "-"' "$md_file" 2>/dev/null || echo "-")
    local need=$(yq eval --front-matter=extract '.need // "-"' "$md_file" 2>/dev/null || echo "-")
    local review=$(yq eval --front-matter=extract '.review // ""' "$md_file" 2>/dev/null || echo "")

    local effective_status="$status"
    if [ -n "$review" ]; then
        effective_status=$(echo "$review" | cut -d'|' -f1 | tr -d ' ')
    fi

    local latest=$(grep "\\[task: $effective_status\\] $id(" "$WORLD_LOG" 2>/dev/null | tail -1 || echo "")

    if [ -z "$latest" ]; then
        "$LOG_CMD" task "$effective_status" "$id" "$title" "$wait" "$need"
        log "[SYNC] $id → $effective_status"
    fi
}

sync_all() {
    for md_file in "$TASKS_DIR"/*.md; do
        [ -e "$md_file" ] || continue
        sync_to_log "$md_file"
    done
}

spawn_pending() {
    for md_file in "$TASKS_DIR"/*.md; do
        [ -e "$md_file" ] || continue

        local id=$(yq eval --front-matter=extract '.id' "$md_file" 2>/dev/null || echo "")
        [ -z "$id" ] && continue

        local status=$(yq eval --front-matter=extract '.status' "$md_file" 2>/dev/null || echo "")
        [ "$status" != "pending" ] && continue

        if [ -f "$PID_DIR/$id.pid" ]; then
            local pid=$(cat "$PID_DIR/$id.pid")
            if kill -0 "$pid" 2>/dev/null; then
                continue
            fi
            rm -f "$PID_DIR/$id.pid"
        fi

        log "[SPAWN] Starting task: $id"
        "$SPAWN_CMD" "$id" &
        sleep 1
    done
}

recover_crashed() {
    for pid_file in "$PID_DIR"/*.pid; do
        [ -e "$pid_file" ] || continue

        local task_id=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")

        if kill -0 "$pid" 2>/dev/null; then
            continue
        fi

        local task_md="$TASKS_DIR/$task_id.md"
        [ -f "$task_md" ] || continue

        local status=$(yq eval --front-matter=extract '.status' "$task_md" 2>/dev/null || echo "")

        if [ "$status" = "running" ]; then
            log "[RECOVER] Crashed task: $task_id (was PID $pid)"
            yq -i --front-matter=process '.status = "pending"' "$task_md"
            rm -f "$pid_file"
            log "[RECOVER] Re-spawning: $task_id"
            "$SPAWN_CMD" "$task_id" &
            sleep 1
        else
            rm -f "$pid_file"
        fi
    done
}

archive_completed() {
    for md_file in "$TASKS_DIR"/*.md; do
        [ -e "$md_file" ] || continue

        local id=$(yq eval --front-matter=extract '.id' "$md_file" 2>/dev/null || echo "")
        [ -z "$id" ] && continue

        local review=$(yq eval --front-matter=extract '.review // ""' "$md_file" 2>/dev/null || echo "")
        [ -z "$review" ] && continue

        local decision=$(echo "$review" | cut -d'|' -f1 | tr -d ' ')
        if [ "$decision" != "verified" ] && [ "$decision" != "canceled" ]; then
            continue
        fi

        local worktree_path="$PROJECT_WORKTREES/$id"
        [ -d "$worktree_path" ] || continue

        log "[ARCHIVE] Moving worktree: $id ($decision)"
        local archive_name="$id-$(date +%Y%m%d-%H%M%S)"
        mv "$worktree_path" "$PROJECT_ARCHIVE/$archive_name"
        git -C "$PROJECT_DIR" worktree prune 2>/dev/null || true
        log "[ARCHIVE] Archived to: $archive_name"
    done
}

run_cycle() {
    sync_all
    spawn_pending
    recover_crashed
    archive_completed
}

# ============================================================
# Main
# ============================================================

case "${1:-start}" in
    start)
        log "=== World Daemon Started ==="
        log "Tasks: $TASKS_DIR"
        log "Log: $WORLD_LOG"
        log "Watching with fswatch..."

        # Check fswatch is installed
        if ! command -v fswatch >/dev/null 2>&1; then
            log "Error: fswatch not installed. Install with: brew install fswatch"
            echo "Error: fswatch not installed. Install with: brew install fswatch" >&2
            exit 1
        fi

        # Initial sync
        run_cycle

        # Watch for changes
        fswatch -o "$TASKS_DIR" | while read -r; do
            log "[EVENT] File change detected"
            run_cycle
        done
        ;;
    once)
        run_cycle
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
