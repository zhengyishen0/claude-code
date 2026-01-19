#!/usr/bin/env bash
# world/run.sh
# World log tool - single source of truth for agent coordination
# New interface: read/write with unified format

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$SCRIPT_DIR/commands"

show_help() {
    cat <<'EOF'
world - Single source of truth for agent coordination

USAGE:
    world create <options>             Create event or task
    world check [options]              Check/read entries

NOTE: Supervisor is now a separate tool. Run 'supervisor' directly.

CREATE COMMANDS:

  Events (facts, one-time):
    world create --event <type> [--session <id>] <content>

  Tasks (to-dos with lifecycle):
    world create --task <id> <status> <trigger> <description> [--need <criteria>]

  Agent (shorthand for event):
    world create --agent <status> <session-id> <content>

CHECK COMMANDS:

    world check                        All entries
    world check --event                Only events
    world check --task                 Only tasks
    world check --event --type <type>  Filter by event type
    world check --task --status <s>    Filter by task status
    world check --session <id>         Filter by session
    world check --since <date>         Filter by time

EXAMPLES:

  # Create events
  world create --event "git:commit" --session abc123 "fix: token refresh"
  world create --event "system" "supervisor started"

  # Create tasks
  world create --task "login-fix" "pending" "now" "修复登录bug" --need "测试通过"
  world create --task "login-fix" "running"
  world create --task "login-fix" "done"

  # Create agent status (shorthand)
  world create --agent start abc123 "开始执行任务"
  world create --agent finish abc123 "任务完成"

  # Check/read
  world check --task --status pending
  world check --event --type "git:commit"
  world check --session abc123

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
    create)
        shift
        "$COMMANDS_DIR/create.sh" "$@"
        ;;
    check)
        shift
        "$COMMANDS_DIR/check.sh" "$@"
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
