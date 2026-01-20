#!/usr/bin/env bash
# supervisor/daemon.sh
# Supervisor daemon - runs both Level 1 and Level 2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../paths.sh"
WORLD_LOG="$PROJECT_DIR/world/world.log"
EVENT_CMD="$PROJECT_DIR/world/commands/event.sh"
LEVEL1="$SCRIPT_DIR/level1.sh"
LEVEL2="$SCRIPT_DIR/level2.sh"

# Configuration
POLL_INTERVAL="${POLL_INTERVAL:-60}"  # seconds
DRY_RUN="${DRY_RUN:-false}"

show_help() {
    cat <<'EOF'
supervisors - Run Level 1 and Level 2 supervisors

USAGE:
    supervisors/run.sh [command]

COMMANDS:
    once        Run both supervisors once (default)
    daemon      Run continuously in foreground
    level1      Run only Level 1 (state enforcer)
    level2      Run only Level 2 (intention verifier)

OPTIONS (via environment):
    POLL_INTERVAL=60    Seconds between checks (daemon mode)
    DRY_RUN=true        Show what would be done without doing it

EXAMPLES:
    supervisors/run.sh once          # Run once
    supervisors/run.sh daemon        # Run continuously
    supervisors/run.sh level1        # Only state enforcement
    supervisors/run.sh level2        # Only verification

SUPERVISOR ROLES:
    Level 1 (State Enforcer):
        - Ensures log state = system state
        - Starts missing agents
        - Kills orphan processes

    Level 2 (Intention Verifier):
        - Verifies agent outputs against criteria
        - Retries with guidance if not verified
        - Handles user input for failed agents
        - Escalates when max retries reached
EOF
}

log_event() {
    local identifier="$1"
    local message="$2"

    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY-RUN] Would log: [event:system][$identifier] $message"
    else
        "$EVENT_CMD" system "$identifier" "$message" >/dev/null
    fi
}

run_once() {
    echo "=== Running Supervisors ==="
    echo ""

    echo ">>> Level 1: State Enforcement"
    DRY_RUN="$DRY_RUN" "$LEVEL1" enforce
    echo ""

    echo ">>> Level 2: Intention Verification"
    DRY_RUN="$DRY_RUN" "$LEVEL2" process
    echo ""

    echo "=== Done ==="
}

run_daemon() {
    echo "Starting supervisor daemon (poll interval: ${POLL_INTERVAL}s)"
    echo "Press Ctrl+C to stop"
    echo ""

    log_event "supervisor-daemon" "started with poll_interval=${POLL_INTERVAL}s"

    trap 'echo ""; echo "Stopping daemon..."; log_event "supervisor-daemon" "stopped"; exit 0' INT TERM

    while true; do
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Running supervisor cycle..."

        # Run Level 1
        DRY_RUN="$DRY_RUN" "$LEVEL1" enforce 2>/dev/null || true

        # Run Level 2
        DRY_RUN="$DRY_RUN" "$LEVEL2" process 2>/dev/null || true

        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Cycle complete, sleeping ${POLL_INTERVAL}s..."
        sleep "$POLL_INTERVAL"
    done
}

# Router
case "${1:-once}" in
    once)
        run_once
        ;;
    daemon)
        run_daemon
        ;;
    level1)
        shift || true
        DRY_RUN="$DRY_RUN" "$LEVEL1" "${1:-enforce}"
        ;;
    level2)
        shift || true
        DRY_RUN="$DRY_RUN" "$LEVEL2" "${1:-process}"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'supervisors/run.sh help' for usage"
        exit 1
        ;;
esac
