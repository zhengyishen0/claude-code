#!/bin/bash
# playwright - Cross-platform browser automation with Playwright
# Usage: playwright <command> [args...]
# Chain commands with +: playwright click "button" + wait + recon

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_NAME="$(basename "$SCRIPT_DIR")"
NODE="${NODE:-node}"

# ============================================================================
# Configuration
# ============================================================================

PLAYWRIGHT_WAIT_TIMEOUT=10
PLAYWRIGHT_WAIT_INTERVAL=0.3
PLAYWRIGHT_OPEN_TIMEOUT=15

# Context directory for persistent browser state
PLAYWRIGHT_CONTEXT_DIR="${PLAYWRIGHT_CONTEXT_DIR:-$HOME/.playwright-cli}"

# ============================================================================
# Command: recon
# ============================================================================
cmd_recon() {
  "$NODE" "$SCRIPT_DIR/js/recon.js" "$@"
}

# ============================================================================
# Command: open
# ============================================================================
cmd_open() {
  local URL=$1
  if [ -z "$URL" ]; then
    echo "Usage: open URL" >&2
    exit 1
  fi

  "$NODE" "$SCRIPT_DIR/js/open.js" "$URL"
}

# ============================================================================
# Command: wait
# ============================================================================
cmd_wait() {
  "$NODE" "$SCRIPT_DIR/js/wait.js" "$@"
}

# ============================================================================
# Command: click
# ============================================================================
cmd_click() {
  local SELECTOR="$1"
  if [ -z "$SELECTOR" ]; then
    echo "Usage: click 'selector'" >&2
    exit 1
  fi

  "$NODE" "$SCRIPT_DIR/js/click.js" "$SELECTOR"
}

# ============================================================================
# Command: input
# ============================================================================
cmd_input() {
  local SELECTOR="$1"
  local VALUE="$2"

  if [ -z "$SELECTOR" ] || [ -z "$VALUE" ]; then
    echo "Usage: input 'selector' 'value'" >&2
    exit 1
  fi

  "$NODE" "$SCRIPT_DIR/js/input.js" "$SELECTOR" "$VALUE"
}

# ============================================================================
# Command: close
# ============================================================================
cmd_close() {
  "$NODE" "$SCRIPT_DIR/js/close.js"
}

# ============================================================================
# Command: help
# ============================================================================
cmd_help() {
  echo "$TOOL_NAME - Cross-platform browser automation with Playwright"
  echo ""
  echo "Usage: $TOOL_NAME <command> [args...] [+ command [args...]]..."
  echo ""
  echo "Commands:"
  echo "  recon [--full]           Get page structure as markdown"
  echo "  open URL                 Open URL in new tab/page"
  echo "  wait [selector] [--gone] Wait for DOM/element (10s timeout)"
  echo "  click SELECTOR           Click element by selector"
  echo "  input SELECTOR VALUE     Type text into element"
  echo "  close                    Close browser and cleanup"
  echo "  help                     Show this help message"
  echo ""
  echo "Quick Examples:"
  echo "  $TOOL_NAME open \"https://example.com\""
  echo "  $TOOL_NAME recon"
  echo "  $TOOL_NAME click 'button#submit' + wait + recon"
  echo "  $TOOL_NAME input '#email' 'test@example.com'"
  echo ""
  echo "Environment:"
  echo "  PLAYWRIGHT_CONTEXT_DIR   Browser state directory (default: ~/.playwright-cli)"
  echo ""
  echo "For detailed documentation, see: $SCRIPT_DIR/README.md"
}

# ============================================================================
# Execute single command
# ============================================================================
execute_single() {
  local cmd="$1"
  shift
  case "$cmd" in
    recon)      cmd_recon "$@" ;;
    open)       cmd_open "$@" ;;
    wait)       cmd_wait "$@" ;;
    click)      cmd_click "$@" ;;
    input)      cmd_input "$@" ;;
    close)      cmd_close "$@" ;;
    help|--help|-h) cmd_help ;;
    *)
      echo "Unknown command: $cmd" >&2
      return 1
      ;;
  esac
}

# ============================================================================
# Execute chain of commands separated by +
# ============================================================================
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

# ============================================================================
# Main execution
# ============================================================================

# Check if + is in args for command chaining
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

# No chain - single command
case "$1" in
  recon)
    shift
    cmd_recon "$@"
    ;;

  open)
    shift
    cmd_open "$@"
    ;;

  wait)
    shift
    cmd_wait "$@"
    ;;

  click)
    shift
    cmd_click "$@"
    ;;

  input)
    shift
    cmd_input "$@"
    ;;

  close)
    cmd_close
    ;;

  help|--help|-h)
    cmd_help
    ;;

  "")
    cmd_help
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run '$TOOL_NAME help' for usage" >&2
    exit 1
    ;;
esac
