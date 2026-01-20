#!/usr/bin/env bash
# supervisor/level2.sh
# Level 2 Supervisor: Intention Verifier (AI-powered)
#
# Job: Ensure every agent reaches verified or failed
# - Verify finish outputs against success criteria
# - Retry with guidance if not verified
# - Escalate to user if max retries reached
# - Handle user input to continue failed agents

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../paths.sh"
WORLD_LOG="$PROJECT_DIR/world/world.log"
AGENT_CMD="$PROJECT_DIR/world/commands/agent.sh"
EVENT_CMD="$PROJECT_DIR/world/commands/event.sh"

# Configuration
MAX_RETRIES="${MAX_RETRIES:-3}"
STALE_THRESHOLD="${STALE_THRESHOLD:-3600}"  # seconds (1 hour)
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

show_help() {
    cat <<'EOF'
level2 - Intention Verifier Supervisor

USAGE:
    level2.sh [command]

COMMANDS:
    check       Check for agents needing attention (default)
    process     Process pending verifications and retries
    status      Show verification status of all agents

OPTIONS (via environment):
    MAX_RETRIES=3       Maximum retry attempts before failing
    STALE_THRESHOLD=3600  Seconds before active agent is considered stale
    DRY_RUN=true        Show what would be done without doing it

EXAMPLES:
    level2.sh check              # Check what needs attention
    level2.sh process            # Process all pending items
    DRY_RUN=true level2.sh process   # Show what would be processed

WHAT IT DOES:
    1. Finds agents with status=finish (pending verification)
    2. Verifies output against success criteria (| need: ...)
    3. Logs [agent:verified] if success, [agent:retry] if not
    4. Finds agents with status=failed + [event:user] input
    5. Logs [agent:retry] to continue failed agents
    6. Escalates to user if max retries reached
EOF
}

verbose() {
    if [ "$VERBOSE" = "true" ]; then
        echo "$@"
    fi
}

# Get the start entry for a session (contains success criteria)
get_start_entry() {
    local session_id="$1"
    grep "\[agent:start\]\[$session_id\]" "$WORLD_LOG" | tail -1 || echo ""
}

# Extract success criteria from start entry
get_success_criteria() {
    local start_entry="$1"
    # Extract text after "| need:"
    echo "$start_entry" | sed -E 's/.*\| need: ?//' || echo ""
}

# Get the last status for a session
get_last_status() {
    local session_id="$1"
    local last_entry
    last_entry=$(grep "\[agent:.*\]\[$session_id\]" "$WORLD_LOG" | tail -1 || echo "")

    if [ -n "$last_entry" ]; then
        echo "$last_entry" | sed -E 's/.*\[agent:([^]]+)\].*/\1/'
    fi
}

# Get the output from finish entry
get_finish_output() {
    local session_id="$1"
    local finish_entry
    finish_entry=$(grep "\[agent:finish\]\[$session_id\]" "$WORLD_LOG" | tail -1 || echo "")

    if [ -n "$finish_entry" ]; then
        # Extract output (everything after the session-id bracket)
        echo "$finish_entry" | sed -E 's/.*\[agent:finish\]\[[^]]+\] ?//'
    fi
}

# Count retry attempts for a session
count_retries() {
    local session_id="$1"
    local count
    count=$(grep -c "\[agent:retry\]\[$session_id\]" "$WORLD_LOG" 2>/dev/null || echo "0")
    echo "$count" | tr -d '[:space:]'
}

# Check if there's user input after a failed status
get_user_input_after_failed() {
    local session_id="$1"

    # Find line number of last failed entry
    local failed_line
    failed_line=$(grep -n "\[agent:failed\]\[$session_id\]" "$WORLD_LOG" | tail -1 | cut -d: -f1 || echo "0")

    if [ "$failed_line" = "0" ]; then
        return
    fi

    # Find user event for this session after the failed line
    local user_event
    user_event=$(tail -n "+$failed_line" "$WORLD_LOG" | grep "\[event:user\]\[$session_id\]" | head -1 || echo "")

    if [ -n "$user_event" ]; then
        # Extract user input (everything after the identifier)
        echo "$user_event" | sed -E 's/.*\[event:user\]\[[^]]+\] ?//'
    fi
}

# Verify output against criteria (simple keyword matching for now)
# In production, this could use AI for smarter verification
verify_output() {
    local output="$1"
    local criteria="$2"

    # Simple verification: check if key terms from criteria appear in output
    # This is a basic implementation - could be enhanced with AI

    # Extract key terms (words > 3 chars, not common words)
    local key_terms
    key_terms=$(echo "$criteria" | tr ' ' '\n' | grep -E '^.{4,}$' | grep -viE '^(with|that|this|from|have|been|will|would|should|could|need|must)$' || echo "")

    if [ -z "$key_terms" ]; then
        # No key terms to match, be lenient
        return 0
    fi

    local matches=0
    local total=0

    for term in $key_terms; do
        ((total++)) || true
        if echo "$output" | grep -qi "$term"; then
            ((matches++)) || true
        fi
    done

    # Require at least 50% of key terms to match
    if [ "$total" -gt 0 ] && [ "$matches" -ge $((total / 2)) ]; then
        return 0  # Verified
    else
        return 1  # Not verified
    fi
}

# Log agent status
log_agent() {
    local status="$1"
    local session_id="$2"
    local message="$3"

    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY-RUN] Would log: [agent:$status][$session_id] $message"
    else
        "$AGENT_CMD" "$status" "$session_id" "$message"
    fi
}

# Log event
log_event() {
    local source="$1"
    local identifier="$2"
    local message="$3"

    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY-RUN] Would log: [event:$source][$identifier] $message"
    else
        "$EVENT_CMD" "$source" "$identifier" "$message"
    fi
}

# Get all unique session IDs
get_all_sessions() {
    if [ ! -f "$WORLD_LOG" ]; then
        return
    fi

    grep -oE '\[agent:[^]]+\]\[[^]]+\]' "$WORLD_LOG" 2>/dev/null | \
        sed -E 's/\[agent:[^]]+\]\[([^]]+)\]/\1/' | \
        sort -u || echo ""
}

cmd_check() {
    echo "=== Level 2 Verification Check ==="

    if [ ! -f "$WORLD_LOG" ]; then
        echo "No world.log found"
        return
    fi

    local sessions
    sessions=$(get_all_sessions)

    if [ -z "$sessions" ]; then
        echo "No agents found"
        return
    fi

    local pending_verification=0
    local awaiting_user=0
    local ready_to_retry=0

    echo ""
    echo "Agents needing attention:"

    for sid in $sessions; do
        local status
        status=$(get_last_status "$sid")

        case "$status" in
            finish)
                echo "  [$sid] status=finish - pending verification"
                ((pending_verification++)) || true
                ;;
            failed)
                local user_input
                user_input=$(get_user_input_after_failed "$sid")
                if [ -n "$user_input" ]; then
                    echo "  [$sid] status=failed + user input - ready to retry"
                    ((ready_to_retry++)) || true
                else
                    echo "  [$sid] status=failed - awaiting user input"
                    ((awaiting_user++)) || true
                fi
                ;;
        esac
    done

    echo ""
    echo "Summary:"
    echo "  Pending verification: $pending_verification"
    echo "  Ready to retry (user input received): $ready_to_retry"
    echo "  Awaiting user input: $awaiting_user"
}

cmd_process() {
    echo "=== Level 2 Processing ==="

    if [ ! -f "$WORLD_LOG" ]; then
        echo "No world.log found"
        return
    fi

    local sessions
    sessions=$(get_all_sessions)

    if [ -z "$sessions" ]; then
        echo "No agents to process"
        return
    fi

    local processed=0

    for sid in $sessions; do
        local status
        status=$(get_last_status "$sid")

        case "$status" in
            finish)
                echo ""
                echo "Processing [$sid] (status=finish)..."

                # Get success criteria and output
                local start_entry
                start_entry=$(get_start_entry "$sid")
                local criteria
                criteria=$(get_success_criteria "$start_entry")
                local output
                output=$(get_finish_output "$sid")

                echo "  Criteria: $criteria"
                echo "  Output: $output"

                if [ -z "$criteria" ]; then
                    echo "  No criteria found, auto-verifying"
                    log_agent "verified" "$sid" "no criteria specified, auto-verified"
                    ((processed++)) || true
                elif verify_output "$output" "$criteria"; then
                    echo "  ✓ Verified - output meets criteria"
                    log_agent "verified" "$sid" "success criteria met"
                    ((processed++)) || true
                else
                    local retries
                    retries=$(count_retries "$sid")
                    echo "  ✗ Not verified (retries: $retries/$MAX_RETRIES)"

                    if [ "$retries" -ge "$MAX_RETRIES" ]; then
                        echo "  Max retries reached, failing agent"
                        log_agent "failed" "$sid" "max retries reached, criteria not met | need: manual review"
                        log_event "system" "$sid" "escalated to user - max retries reached"
                    else
                        echo "  Scheduling retry"
                        log_agent "retry" "$sid" "output does not match criteria: $criteria"
                    fi
                    ((processed++)) || true
                fi
                ;;

            failed)
                local user_input
                user_input=$(get_user_input_after_failed "$sid")

                if [ -n "$user_input" ]; then
                    echo ""
                    echo "Processing [$sid] (status=failed + user input)..."
                    echo "  User input: $user_input"
                    echo "  Scheduling retry with user input"
                    log_agent "retry" "$sid" "user provided: $user_input"
                    ((processed++)) || true
                fi
                ;;
        esac
    done

    echo ""
    echo "Processed: $processed agents"
}

cmd_status() {
    echo "=== Agent Verification Status ==="

    if [ ! -f "$WORLD_LOG" ]; then
        echo "No world.log found"
        return
    fi

    local sessions
    sessions=$(get_all_sessions)

    if [ -z "$sessions" ]; then
        echo "No agents found"
        return
    fi

    echo ""
    printf "%-15s %-12s %-8s %s\n" "SESSION-ID" "STATUS" "RETRIES" "CRITERIA"
    printf "%-15s %-12s %-8s %s\n" "----------" "------" "-------" "--------"

    for sid in $sessions; do
        local status retries criteria
        status=$(get_last_status "$sid")
        retries=$(count_retries "$sid")

        local start_entry
        start_entry=$(get_start_entry "$sid")
        criteria=$(get_success_criteria "$start_entry")
        criteria="${criteria:0:40}"  # Truncate

        printf "%-15s %-12s %-8s %s\n" "$sid" "$status" "$retries" "$criteria"
    done
}

# Router
case "${1:-check}" in
    check)
        cmd_check
        ;;
    process)
        cmd_process
        ;;
    status)
        cmd_status
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'level2.sh help' for usage"
        exit 1
        ;;
esac
