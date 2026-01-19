#!/usr/bin/env bash
# world/run.sh
# World log tool - single source of truth for agent coordination
# New interface: read/write with unified format

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$SCRIPT_DIR/commands"
SUPERVISORS_DIR="$SCRIPT_DIR/supervisors"

show_help() {
    cat <<'EOF'
world - Single source of truth for agent coordination

USAGE:
    world write <options>              Write event or task
    world read [options]               Read entries
    world supervisor [command]         Run supervisors

WRITE COMMANDS:

  Events (facts, one-time):
    world write --event <type> [--session <id>] <content>

  Tasks (to-dos with lifecycle):
    world write --task <id> <status> <trigger> <description> [--need <criteria>]

  Agent (shorthand for event):
    world write --agent <status> <session-id> <content>

READ COMMANDS:

    world read                         All entries
    world read --event                 Only events
    world read --task                  Only tasks
    world read --event --type <type>   Filter by event type
    world read --task --status <s>     Filter by task status
    world read --session <id>          Filter by session
    world read --since <date>          Filter by time

EXAMPLES:

  # Write events
  world write --event "git:commit" --session abc123 "fix: token refresh"
  world write --event "system" "supervisor started"

  # Write tasks
  world write --task "login-fix" "pending" "now" "修复登录bug" --need "测试通过"
  world write --task "login-fix" "running"
  world write --task "login-fix" "done"

  # Write agent status (shorthand)
  world write --agent start abc123 "开始执行任务"
  world write --agent finish abc123 "任务完成"

  # Read
  world read --task --status pending
  world read --event --type "git:commit"
  world read --session abc123

DATA FORMAT:

  Event:  [timestamp] [event] <type> | <content>
  Task:   [timestamp] [task] <id> | <status> | <trigger> | <description> | need: <criteria>

TASK STATUSES:
  pending, running, done, failed

EVENT TYPES:
  git:commit, git:push, system, user, task:<id>, browser, file, api
EOF
}

# Route to command
case "${1:-}" in
    write)
        shift
        "$COMMANDS_DIR/write.sh" "$@"
        ;;
    read)
        shift
        "$COMMANDS_DIR/read.sh" "$@"
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
