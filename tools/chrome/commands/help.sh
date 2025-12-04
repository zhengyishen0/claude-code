#!/bin/bash
# help.sh - Show help (dynamically assembled from commands)
# Usage: help.sh [TOOL_NAME]

if [[ "$1" == "--help" ]]; then
  echo "help, h                     Show this help message"
  exit 0
fi

CMD_DIR="$(dirname "$0")"
TOOL_NAME="${1:-$(basename "$(dirname "$CMD_DIR")")}"

echo "$TOOL_NAME - Browser automation with React/SPA support"
echo ""
echo "Usage: $TOOL_NAME <command> [args...] [+ command [args...]]..."
echo ""
echo "Commands:"
for cmd in recon open wait click input esc tabs info close help; do
  "$CMD_DIR/$cmd.sh" --help | head -1 | sed 's/^/  /'
done
echo ""
echo "Chaining with +:"
echo "  click \"[@Submit](#btn)\" + wait + recon"
echo "  click \"[@Close](#btn)\" + wait \"[role=dialog]\" --gone + recon"
echo "  input --aria Search tokyo + wait \"[role=listbox]\" + recon Form"
echo ""
echo "Key Principles:"
echo "  1. Recon first - understand page before interacting"
echo "  2. Chain with + - action + wait + recon in one call"
echo "  3. Wait for specific element - not just any DOM change"
echo "  4. Use --gone when expecting element to disappear"
echo "  5. Scope recon with -S to see only relevant section"
echo "  6. URL params > clicking - faster and more reliable"
echo ""
echo "Raw chrome-cli:"
echo "  list tabs | info | open URL | activate -t ID | execute JS"
