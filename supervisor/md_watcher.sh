#!/usr/bin/env bash
# supervisor/md_watcher.sh
# Watch tasks/*.md and sync to world.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORLD_LOG="$PROJECT_DIR/world/world.log"
TASKS_DIR="$PROJECT_DIR/tasks"

# Ensure dependencies
if ! command -v yq >/dev/null 2>&1; then
    echo "Error: yq not installed. Install with: brew install yq"
    exit 1
fi

# Ensure directories exist
mkdir -p "$TASKS_DIR"
touch "$WORLD_LOG"

sync_task_to_log() {
    local md_file="$1"
    [ -f "$md_file" ] || return 0

    # Parse frontmatter
    local id=$(yq eval --front-matter=extract '.id' "$md_file" 2>/dev/null || echo "")
    [ -z "$id" ] && return 0

    local status=$(yq eval --front-matter=extract '.status' "$md_file" 2>/dev/null || echo "pending")
    local title=$(yq eval --front-matter=extract '.title' "$md_file" 2>/dev/null || echo "Untitled")
    local wait=$(yq eval --front-matter=extract '.wait // "-"' "$md_file" 2>/dev/null || echo "-")
    local need=$(yq eval --front-matter=extract '.need // "-"' "$md_file" 2>/dev/null || echo "-")

    # Check latest status in log
    local latest=$(grep "\\[task:.*\\] $id(" "$WORLD_LOG" 2>/dev/null | tail -1 || echo "")

    # If status changed, write new entry
    if [[ "$latest" != *"[task: $status]"* ]]; then
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local entry="[$timestamp] [task: $status] $id($title) | file: tasks/$id.md | wait: $wait | need: $need"
        echo "$entry" >> "$WORLD_LOG"
        echo "[$timestamp] Synced: $id → $status"

        # If new pending task, spawn it
        if [ "$status" = "pending" ] && ! [ -f "/tmp/supervisor/pids/$id.pid" ]; then
            echo "  → Spawning task: $id"
            "$SCRIPT_DIR/spawn_task.sh" "$id" &
        fi
    fi
}

# Initial sync
echo "=== MD Watcher Started ==="
echo "Syncing existing tasks..."
for md_file in "$TASKS_DIR"/*.md; do
    [ -e "$md_file" ] || continue
    sync_task_to_log "$md_file"
done

# Watch for changes
echo "Watching tasks/*.md for changes..."
if command -v fswatch >/dev/null 2>&1; then
    # Use fswatch if available (better for macOS)
    fswatch -0 -r "$TASKS_DIR" 2>/dev/null | while read -d "" event; do
        [[ "$event" == *.md ]] || continue
        sync_task_to_log "$event"
    done
else
    # Fallback: polling
    echo "Note: fswatch not found, using polling. Install with: brew install fswatch"
    declare -A last_modified

    while true; do
        for md_file in "$TASKS_DIR"/*.md; do
            [ -e "$md_file" ] || continue

            current_mtime=$(stat -f %m "$md_file" 2>/dev/null || echo "0")
            last_mtime="${last_modified[$md_file]:-0}"

            if [ "$current_mtime" != "$last_mtime" ]; then
                last_modified[$md_file]="$current_mtime"
                sync_task_to_log "$md_file"
            fi
        done
        sleep 2
    done
fi
