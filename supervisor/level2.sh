#!/usr/bin/env bash
# supervisor/level2.sh
# Level 2 Supervisor: Intention Verifier
#
# Job: Verify completed tasks against success criteria
# - Find tasks with status: done
# - Verify output against 'need' criteria
# - Update status to verified/retry/failed

set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

TASKS_DIR="$PROJECT_DIR/world/tasks"

MAX_RETRIES="${MAX_RETRIES:-3}"
DRY_RUN="${DRY_RUN:-false}"

show_help() {
    cat <<'HELP'
level2 - Intention Verifier Supervisor

USAGE:
    level2.sh [command]

COMMANDS:
    check       Show tasks needing verification
    process     Verify and update task statuses
    status      Show all task statuses

OPTIONS (via environment):
    MAX_RETRIES=3       Maximum retry attempts
    DRY_RUN=true        Show without executing
HELP
}

# Update task MD status
update_task_status() {
    local task_file="$1"
    local new_status="$2"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY-RUN] Would update $task_file → status: $new_status"
    else
        yq -i --front-matter=process ".status = \"$new_status\"" "$task_file"
        echo "Updated: $(basename "$task_file") → $new_status"
    fi
}

# Count retries for a task
count_retries() {
    local task_file="$1"
    yq eval --front-matter=extract '.retries // 0' "$task_file" 2>/dev/null || echo "0"
}

# Increment retry count
increment_retries() {
    local task_file="$1"
    local current=$(count_retries "$task_file")
    local new=$((current + 1))
    
    if [ "$DRY_RUN" != "true" ]; then
        yq -i --front-matter=process ".retries = $new" "$task_file"
    fi
    echo "$new"
}

# Simple keyword matching for verification
verify_output() {
    local task_file="$1"
    local need=$(yq eval --front-matter=extract '.need // "-"' "$task_file" 2>/dev/null)
    
    [ "$need" = "-" ] && return 0  # No criteria = auto-pass
    
    # Check if task body contains key terms from need
    local body=$(sed -n '/^---$/,/^---$/!p' "$task_file")
    local match_count=0
    local total=0
    
    for word in $need; do
        [ ${#word} -lt 4 ] && continue
        total=$((total + 1))
        echo "$body" | grep -qi "$word" && match_count=$((match_count + 1))
    done
    
    [ "$total" -eq 0 ] && return 0
    [ "$match_count" -ge $((total / 2)) ] && return 0
    return 1
}

cmd_check() {
    echo "=== Tasks Needing Verification ==="
    
    for task_file in "$TASKS_DIR"/*.md; do
        [ -e "$task_file" ] || continue
        
        local status=$(yq eval --front-matter=extract '.status' "$task_file" 2>/dev/null)
        local id=$(yq eval --front-matter=extract '.id' "$task_file" 2>/dev/null)
        
        [ "$status" = "done" ] && echo "  $id (done → needs verification)"
    done
}

cmd_process() {
    echo "=== Processing Tasks ==="
    
    for task_file in "$TASKS_DIR"/*.md; do
        [ -e "$task_file" ] || continue
        
        local status=$(yq eval --front-matter=extract '.status' "$task_file" 2>/dev/null)
        local id=$(yq eval --front-matter=extract '.id' "$task_file" 2>/dev/null)
        
        [ "$status" != "done" ] && continue
        
        echo ""
        echo "Processing: $id"
        
        if verify_output "$task_file"; then
            echo "  ✓ Verified"
            update_task_status "$task_file" "verified"
        else
            local retries=$(increment_retries "$task_file")
            if [ "$retries" -ge "$MAX_RETRIES" ]; then
                echo "  ✗ Failed (max retries: $retries)"
                update_task_status "$task_file" "failed"
            else
                echo "  → Retry ($retries/$MAX_RETRIES)"
                update_task_status "$task_file" "pending"
            fi
        fi
    done
}

cmd_status() {
    echo "=== Task Statuses ==="
    printf "%-15s %-12s %-8s %s\n" "ID" "STATUS" "RETRIES" "NEED"
    printf "%-15s %-12s %-8s %s\n" "---" "------" "-------" "----"
    
    for task_file in "$TASKS_DIR"/*.md; do
        [ -e "$task_file" ] || continue
        
        local id=$(yq eval --front-matter=extract '.id' "$task_file" 2>/dev/null)
        local status=$(yq eval --front-matter=extract '.status' "$task_file" 2>/dev/null)
        local retries=$(yq eval --front-matter=extract '.retries // 0' "$task_file" 2>/dev/null)
        local need=$(yq eval --front-matter=extract '.need // "-"' "$task_file" 2>/dev/null)
        
        printf "%-15s %-12s %-8s %s\n" "$id" "$status" "$retries" "${need:0:30}"
    done
}

# Ensure yq
command -v yq >/dev/null || { echo "Error: yq required"; exit 1; }

case "${1:-check}" in
    check)   cmd_check ;;
    process) cmd_process ;;
    status)  cmd_status ;;
    help|-h) show_help ;;
    *)       echo "Unknown: $1"; exit 1 ;;
esac
