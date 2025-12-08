#!/bin/bash
# help.sh - Show help (dynamically assembled from commands)
# Usage: help.sh [TOOL_NAME]

if [[ "$1" == "--help" ]]; then
  echo "help                        Show this help message"
  exit 0
fi

CMD_DIR="$(dirname "$0")"
TOOL_NAME="${1:-$(basename "$(dirname "$CMD_DIR")")}"
TOOL_DIR="$(dirname "$CMD_DIR")"

echo "$TOOL_NAME - Browser automation with React/SPA support"
echo ""
echo "Usage: $TOOL_NAME <command> [args...] [+ command [args...]]..."
echo ""
echo "Commands:"
echo "  recon [--full] [--status]  Get page structure as markdown"
echo "  open URL [--status]      Open URL (waits for load), then recon"
echo "  wait [sel] [--gone]  Wait for DOM/element (10s timeout)"
echo "  click SELECTOR          Click element by CSS selector"
echo "  input SELECTOR VALUE    Set input value by CSS selector"
echo "  esc                         Send ESC key (close dialogs/modals)"
echo "  help                        Show this help message"
echo ""
echo "Quick Examples:"
echo "  $TOOL_NAME open \"https://example.com\""
echo "  $TOOL_NAME recon"
echo "  $TOOL_NAME click '[data-testid=\"btn\"]' + wait + recon"
echo "  $TOOL_NAME input '#email' 'test@example.com' + wait + recon"
echo ""
echo "For detailed documentation, see: $TOOL_DIR/README.md"
