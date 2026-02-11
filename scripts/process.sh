#!/usr/bin/env bash
# utils/process.sh
# ZFC (Zero File-based State) process management
#
# Principle: Query the system, don't maintain state files.
# The process table IS the source of truth.

set -euo pipefail

# Pattern for matching task agents (anchored to avoid false matches)
_TASK_AGENT_PATTERN='claude.*--session-id'

# Check if a task agent is running by session_id
# Usage: is_task_running <session_id>
# Returns: 0 if running, 1 if not
is_task_running() {
    local session_id="$1"
    [ -z "$session_id" ] && return 1
    pgrep -f "${_TASK_AGENT_PATTERN} ${session_id}" >/dev/null 2>&1
}

# Get PID of running task (for logging/debugging)
# Usage: get_task_pid <session_id>
# Returns: PID or empty string
get_task_pid() {
    local session_id="$1"
    [ -z "$session_id" ] && return 1
    pgrep -f "${_TASK_AGENT_PATTERN} ${session_id}" 2>/dev/null | head -1
}

# Kill task by session_id (graceful with escalation)
# Usage: kill_task <session_id>
# Returns: 0 on success (or if not running), 1 on error
kill_task() {
    local session_id="$1"
    [ -z "$session_id" ] && return 1

    if ! is_task_running "$session_id"; then
        return 0  # Already not running
    fi

    # Phase 1: Graceful kill
    pkill -f "${_TASK_AGENT_PATTERN} ${session_id}" 2>/dev/null || true

    # Wait briefly for process to die
    local attempts=0
    while is_task_running "$session_id" && [ $attempts -lt 10 ]; do
        sleep 0.1
        attempts=$((attempts + 1))
    done

    # Phase 2: Force kill if still alive
    if is_task_running "$session_id"; then
        pkill -9 -f "${_TASK_AGENT_PATTERN} ${session_id}" 2>/dev/null || true
    fi

    return 0
}

# List all running task agents (for observability)
# Usage: list_running_tasks
# Output: session_id PID (one per line)
list_running_tasks() {
    local output
    output=$(pgrep -af "${_TASK_AGENT_PATTERN}" 2>/dev/null) || true
    [ -z "$output" ] && return 0

    echo "$output" | while read -r pid cmd; do
        local session_id
        session_id=$(echo "$cmd" | grep -oE '\-\-session-id [^ ]+' | cut -d' ' -f2)
        [ -n "$session_id" ] && echo "$session_id $pid"
    done
}

# Get all running session IDs (batch operation for efficiency)
# Usage: get_running_session_ids
# Output: One session_id per line
get_running_session_ids() {
    list_running_tasks | cut -d' ' -f1
}
