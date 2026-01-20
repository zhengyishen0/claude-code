#!/usr/bin/env bash
# world/commands/watch.sh
# Daemon: sync MD to log, spawn pending, recover crashed, archive completed

set -euo pipefail

# Source paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../paths.sh"

SPAWN_CMD="$(dirname "${BASH_SOURCE[0]}")/spawn.sh"

# Ensure directories exist
mkdir -p "$PID_DIR" "$PROJECT_WORKTREES" "$PROJECT_ARCHIVE" "$TASKS_DIR"

# Interval between checks (seconds)
INTERVAL="${1:-5}"

show_help() {
    cat <<'HELP'
watch - World daemon: observe and react

USAGE:
    watch [interval]

DESCRIPTION:
    Runs continuously, performing:
    1. SYNC: MD changes → world.log
    2. SPAWN: pending tasks in log → start agents
    3. RECOVER: dead PIDs with running status → re-spawn
    4. ARCHIVE: verified/canceled → move worktree to archive

    Default interval: 5 seconds

WORKTREE STRUCTURE:
    $PROJECT_WORKTREES/
    ├── <active-worktrees>/
    └── .archive/
        └── <archived-worktrees>/

EXAMPLES:
    world watch         # Run with 5s interval
    world watch 10      # Run with 10s interval
HELP
}

if [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi

# Ensure yq is installed
if ! command -v yq >/dev/null 2>&1; then
    echo "Error: yq not installed. Install with: brew install yq" >&2
    exit 1
fi

# ============================================================
# SYNC: MD → world.log
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

    # Determine effective status (review overrides status)
    local effective_status="$status"
    if [ -n "$review" ]; then
        effective_status=$(echo "$review" | cut -d'|' -f1 | tr -d ' ')
    fi

    # Check if this status is already in log
    local latest=$(grep "\\[task: $effective_status\\] $id(" "$WORLD_LOG" 2>/dev/null | tail -1 || echo "")

    if [ -z "$latest" ]; then
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local entry="[$timestamp] [task: $effective_status] $id($title) | file: tasks/$id.md | wait: $wait | need: $need"
        echo "$entry" >> "$WORLD_LOG"
        echo "[SYNC] $id → $effective_status"
    fi
}

sync_all() {
    for md_file in "$TASKS_DIR"/*.md; do
        [ -e "$md_file" ] || continue
        sync_to_log "$md_file"
    done
}

# ============================================================
# SPAWN: pending in log → start agent
# ============================================================
spawn_pending() {
    for md_file in "$TASKS_DIR"/*.md; do
        [ -e "$md_file" ] || continue

        local id=$(yq eval --front-matter=extract '.id' "$md_file" 2>/dev/null || echo "")
        [ -z "$id" ] && continue

        local status=$(yq eval --front-matter=extract '.status' "$md_file" 2>/dev/null || echo "")
        [ "$status" != "pending" ] && continue

        # Check if already has PID
        if [ -f "$PID_DIR/$id.pid" ]; then
            local pid=$(cat "$PID_DIR/$id.pid")
            if kill -0 "$pid" 2>/dev/null; then
                continue  # Already running
            fi
            rm -f "$PID_DIR/$id.pid"  # Stale PID
        fi

        echo "[SPAWN] Starting task: $id"
        "$SPAWN_CMD" "$id" &
        sleep 1  # Avoid race conditions
    done
}

# ============================================================
# RECOVER: dead PID + running status → re-spawn
# ============================================================
recover_crashed() {
    for pid_file in "$PID_DIR"/*.pid; do
        [ -e "$pid_file" ] || continue

        local task_id=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")

        # Check if process is running
        if kill -0 "$pid" 2>/dev/null; then
            continue  # Still running
        fi

        # Process dead, check task status
        local task_md="$TASKS_DIR/$task_id.md"
        [ -f "$task_md" ] || continue

        local status=$(yq eval --front-matter=extract '.status' "$task_md" 2>/dev/null || echo "")

        if [ "$status" = "running" ]; then
            echo "[RECOVER] Crashed task: $task_id (was PID $pid)"
            
            # Reset to pending
            yq -i --front-matter=process '.status = "pending"' "$task_md"
            rm -f "$pid_file"

            # Re-spawn
            echo "[RECOVER] Re-spawning: $task_id"
            "$SPAWN_CMD" "$task_id" &
            sleep 1
        else
            # Task completed/failed normally, just clean up PID
            rm -f "$pid_file"
        fi
    done
}

# ============================================================
# ARCHIVE: verified/canceled → move worktree
# ============================================================
archive_completed() {
    for md_file in "$TASKS_DIR"/*.md; do
        [ -e "$md_file" ] || continue

        local id=$(yq eval --front-matter=extract '.id' "$md_file" 2>/dev/null || echo "")
        [ -z "$id" ] && continue

        local review=$(yq eval --front-matter=extract '.review // ""' "$md_file" 2>/dev/null || echo "")
        [ -z "$review" ] && continue

        # Check if verified or canceled
        local decision=$(echo "$review" | cut -d'|' -f1 | tr -d ' ')
        if [ "$decision" != "verified" ] && [ "$decision" != "canceled" ]; then
            continue
        fi

        # Check for worktree
        local worktree_path="$PROJECT_WORKTREES/$id"
        [ -d "$worktree_path" ] || continue

        echo "[ARCHIVE] Moving worktree: $id ($decision)"

        # Archive
        local archive_name="$id-$(date +%Y%m%d-%H%M%S)"
        mv "$worktree_path" "$PROJECT_ARCHIVE/$archive_name"

        # Prune git worktree reference
        git -C "$PROJECT_DIR" worktree prune 2>/dev/null || true

        echo "[ARCHIVE] Archived to: $PROJECT_ARCHIVE/$archive_name"
    done
}

# ============================================================
# MAIN LOOP
# ============================================================
echo "=== World Watch Daemon ==="
echo "Interval: ${INTERVAL}s"
echo "Tasks: $TASKS_DIR"
echo "Log: $WORLD_LOG"
echo "Worktrees: $PROJECT_WORKTREES"
echo "Archive: $PROJECT_ARCHIVE"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Trap for clean exit
trap 'echo ""; echo "Watch stopped."; exit 0' INT TERM

# Initial sync
echo "Initial sync..."
sync_all
echo ""

# Main loop
while true; do
    sync_all
    spawn_pending
    recover_crashed
    archive_completed
    sleep "$INTERVAL"
done
