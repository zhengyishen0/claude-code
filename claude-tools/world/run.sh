#!/usr/bin/env bash
# claude-tools/world/run.sh
# World log tool - single source of truth for agent coordination

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$SCRIPT_DIR/commands"
SUPERVISORS_DIR="$SCRIPT_DIR/supervisors"

show_help() {
    cat <<'EOF'
world - Single source of truth for agent coordination

USAGE:
    world event <source> <identifier> <output>    Log an event
    world agent <status> <session-id> <output>    Log agent status
    world check [agent-id]                        Read new entries
    world query <type>                            Query the log
    world respond <session-id> <response>         Human response to failed agent
    world supervisor [command]                    Run supervisors

EXAMPLES:
    # Log events
    world event chrome "airbnb.com" "clicked Search, 24 results"
    world event bash "git-status" "clean working directory"
    world event file "src/config.json" "modified"
    world event user "abc123" "captcha solved: boats"

    # Log agent lifecycle
    world agent start abc123 "Book Tokyo flights | need: confirmation number"
    world agent active abc123 "searching flights"
    world agent finish abc123 "Booked JAL $450, confirmation #XYZ"
    world agent verified abc123 "success criteria met"
    world agent retry abc123 "prices not found, try again"
    world agent failed abc123 "captcha required | need: solve captcha"

    # Check for new entries
    world check                    # Anonymous check
    world check manager-xyz        # Check as specific agent

    # Query
    world query active             # Active agents
    world query pending            # Agents awaiting verification
    world query failed             # Failed agents

    # Human-in-the-loop
    world respond abc123 "captcha solved: boats"

    # Run supervisors
    world supervisor once          # Run once
    world supervisor level1        # Only state enforcement
    world supervisor level2        # Only verification

FORMAT:
    Events:  [timestamp][event:source][identifier] output
    Agents:  [timestamp][agent:status][session-id] output | need: criteria

EVENT SOURCES:
    chrome, bash, file, api, system, user

AGENT STATUSES:
    start, active, finish, verified, retry, failed
EOF
}

# Route to command
case "${1:-}" in
    event)
        shift
        "$COMMANDS_DIR/event.sh" "$@"
        ;;
    agent)
        shift
        "$COMMANDS_DIR/agent.sh" "$@"
        ;;
    check)
        shift
        "$COMMANDS_DIR/check.sh" "$@"
        ;;
    query)
        shift
        "$COMMANDS_DIR/query.sh" "$@"
        ;;
    respond)
        shift
        "$COMMANDS_DIR/respond.sh" "$@"
        ;;
    supervisor|supervisors)
        shift
        "$SUPERVISORS_DIR/run.sh" "$@"
        ;;
    help|-h|--help|"")
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'world help' for usage"
        exit 1
        ;;
esac
