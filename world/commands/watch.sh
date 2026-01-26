#!/usr/bin/env bash
# world/commands/watch.sh
# Daemon: sync MD to log, spawn pending, recover crashed, archive completed

set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

# ZFC: Source process utilities
source "$PROJECT_DIR/utils/process.sh"

TASKS_DIR="$PROJECT_DIR/task/data"
WORLD_LOG="$PROJECT_DIR/world/world.log"
PROJECT_WORKTREES="$(dirname "$PROJECT_DIR")/.worktrees/$(basename "$PROJECT_DIR")"
PROJECT_ARCHIVE="$PROJECT_WORKTREES/.archive"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

SPAWN_CMD="$PROJECT_DIR/world/commands/spawn.sh"
RECORD_CMD="$PROJECT_DIR/world/commands/record.sh"

# Worktree paths
WORKTREE_BASE="$PROJECT_WORKTREES"
ARCHIVE_DIR="$PROJECT_ARCHIVE"

mkdir -p "$WORKTREE_BASE" "$ARCHIVE_DIR" "$TASKS_DIR"

# Interval between checks (seconds)
INTERVAL="${1:-5}"

show_help() {
    cat <<'EOF'
watch - World daemon: observe and react

USAGE:
    watch [interval]

DESCRIPTION:
    Runs continuously, performing:
    1. SYNC: MD changes → world.log
    2. SPAWN: pending tasks → start agents
    3. RECOVER: crashed tasks (status:running but no process) → re-spawn
    4. ARCHIVE: verified/canceled → move worktree to archive

    Uses ZFC (Zero File-based State): queries process table directly,
    no PID files to manage or clean up.

    Default interval: 5 seconds

WORKTREE STRUCTURE:
    $BASE_DIR/.worktrees/<project>/
    ├── <task-id>/           # Active worktrees
    └── .archive/
        └── <task-id>-<ts>/  # Archived worktrees

EXAMPLES:
    world watch         # Run with 5s interval
    world watch 10      # Run with 10s interval
EOF
}

if [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
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
        # review format: "verified | supervisor-id" or "canceled | supervisor-id"
        effective_status=$(echo "$review" | cut -d'|' -f1 | tr -d ' ')
    fi

    # Check if this status is already in log
    local latest=$(grep "\\[task: $effective_status\\] $id(" "$WORLD_LOG" 2>/dev/null | tail -1 || echo "")

    if [ -z "$latest" ]; then
        "$RECORD_CMD" task "$effective_status" "$id" "$title" "$wait" "$need"
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
# SPAWN: pending tasks → start agent (ZFC)
# ============================================================
spawn_pending() {
    for md_file in "$TASKS_DIR"/*.md; do
        [ -e "$md_file" ] || continue

        local id=$(yq eval --front-matter=extract '.id' "$md_file" 2>/dev/null || echo "")
        [ -z "$id" ] && continue

        local status=$(yq eval --front-matter=extract '.status' "$md_file" 2>/dev/null || echo "")
        [ "$status" != "pending" ] && continue

        local session_id=$(yq eval --front-matter=extract '.session_id' "$md_file" 2>/dev/null || echo "")
        [ -z "$session_id" ] && continue

        # ZFC: Check if already running by session_id
        if is_task_running "$session_id"; then
            continue  # Already running
        fi

        echo "[SPAWN] Starting task: $id"
        "$SPAWN_CMD" "$id" &
        sleep 1  # Avoid race conditions
    done
}

# ============================================================
# RECOVER: crashed tasks (status:running but no process) → re-spawn (ZFC)
# ============================================================
recover_crashed() {
    for md_file in "$TASKS_DIR"/*.md; do
        [ -e "$md_file" ] || continue

        local status=$(yq eval --front-matter=extract '.status' "$md_file" 2>/dev/null || echo "")
        [ "$status" != "running" ] && continue

        local id=$(yq eval --front-matter=extract '.id' "$md_file" 2>/dev/null || echo "")
        local session_id=$(yq eval --front-matter=extract '.session_id' "$md_file" 2>/dev/null || echo "")
        [ -z "$session_id" ] && continue

        # ZFC: Check if process is actually running
        if is_task_running "$session_id"; then
            continue  # Still running, all good
        fi

        # Process dead + status:running = crashed
        echo "[RECOVER] Crashed task: $id (session: $session_id)"

        # Reset to pending for re-spawn
        yq -i --front-matter=process '.status = "pending"' "$md_file"

        # Re-spawn
        echo "[RECOVER] Re-spawning: $id"
        "$SPAWN_CMD" "$id" &
        sleep 1
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

        # Check for worktree - new path structure
        local worktree_path="$WORKTREE_BASE/$id"
        [ -d "$worktree_path" ] || continue

        echo "[ARCHIVE] Moving worktree: $id ($decision)"

        # Archive to .worktrees/<project>/.archive/
        local archive_name="$id-$(date +%Y%m%d-%H%M%S)"
        mv "$worktree_path" "$ARCHIVE_DIR/$archive_name"

        # Prune git worktree reference
        git -C "$PROJECT_DIR" worktree prune 2>/dev/null || true

        echo "[ARCHIVE] Archived to: .worktrees/$PROJECT_NAME/.archive/$archive_name"
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
