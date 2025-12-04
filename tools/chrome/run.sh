#!/bin/bash
# Tool entry point - name derived from folder
# Usage: run.sh <command> [args...]
# Chain commands with +: run.sh click "[@X](#btn)" + wait + recon

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_NAME="$(basename "$SCRIPT_DIR")"
CMD_DIR="$SCRIPT_DIR/commands"

# Execute a single command
execute_single() {
  local cmd="$1"
  shift
  case "$cmd" in
    recon|r)    "$CMD_DIR/recon.sh" "$@" ;;
    open|o)     "$CMD_DIR/open.sh" "$@" ;;
    wait|w)     "$CMD_DIR/wait.sh" "$@" ;;
    click|c)    "$CMD_DIR/click.sh" "$@" ;;
    input|i)    "$CMD_DIR/input.sh" "$@" ;;
    tabs|t)     "$CMD_DIR/tabs.sh" "$@" ;;
    info)       "$CMD_DIR/info.sh" "$@" ;;
    close)      "$CMD_DIR/close.sh" "$@" ;;
    esc|escape) "$CMD_DIR/esc.sh" "$@" ;;
    help|h|--help|-h) "$CMD_DIR/help.sh" "$TOOL_NAME" ;;
    *)
      echo "Unknown command: $cmd" >&2
      return 1
      ;;
  esac
}

# Execute chain of commands separated by +
execute_chain() {
  local cmd="$1"
  shift
  local args=()

  for arg in "$@"; do
    if [ "$arg" = "+" ]; then
      # Execute accumulated command
      execute_single "$cmd" "${args[@]}"
      if [ $? -ne 0 ]; then return 1; fi
      # Reset for next command
      cmd=""
      args=()
    elif [ -z "$cmd" ]; then
      cmd="$arg"
    else
      args+=("$arg")
    fi
  done

  # Execute last command
  if [ -n "$cmd" ]; then
    execute_single "$cmd" "${args[@]}"
  fi
}

# Check if + is in args
has_chain=false
for arg in "$@"; do
  if [ "$arg" = "+" ]; then
    has_chain=true
    break
  fi
done

if [ "$has_chain" = true ]; then
  execute_chain "$@"
  exit $?
fi

# No chain - use original case statement for backward compat
case "$1" in
  recon|r)
    shift
    "$CMD_DIR/recon.sh" "$@"
    ;;

  open|o)
    shift
    "$CMD_DIR/open.sh" "$@"
    ;;

  wait|w)
    shift
    "$CMD_DIR/wait.sh" "$@"
    ;;

  click|c)
    shift
    "$CMD_DIR/click.sh" "$@"
    ;;

  input|i)
    shift
    "$CMD_DIR/input.sh" "$@"
    ;;

  tabs|t)
    "$CMD_DIR/tabs.sh"
    ;;

  info)
    "$CMD_DIR/info.sh"
    ;;

  close)
    shift
    "$CMD_DIR/close.sh" "$@"
    ;;

  esc|escape)
    "$CMD_DIR/esc.sh"
    ;;

  help|h|--help|-h)
    "$CMD_DIR/help.sh" "$TOOL_NAME"
    ;;

  "")
    "$CMD_DIR/help.sh" "$TOOL_NAME"
    echo ""
    "$CMD_DIR/prereq.sh"
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run '$TOOL_NAME help' for usage" >&2
    exit 1
    ;;
esac
