#!/bin/bash
# chrome-cli-plus - Enhanced chrome-cli with React/SPA support
# Usage: chrome-cli-plus <command> [args...]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMD_DIR="$SCRIPT_DIR/commands"

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
    "$CMD_DIR/help.sh"
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run 'chrome-cli-plus help' for usage" >&2
    exit 1
    ;;
esac
