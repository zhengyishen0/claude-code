#!/bin/bash
# help.sh - Show help (dynamically assembled from commands)
# Usage: help.sh [TOOL_NAME]

if [[ "$1" == "--help" ]]; then
  echo "help                        Show this help message"
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
echo "Element Formats (universal across recon/click/input):"
echo "  Actionable: [text@aria](#id|#testid|.selector|/path)"
echo "    Examples: [@Search](#btn), [Submit](#submit-btn), [Next](/path)"
echo "    Usage: click \"[@Search](#btn)\""
echo "  Input fields: Input: aria=\"label\" (type)"
echo "    Examples: Input: aria=\"Where\" (search), Input: aria=\"Email\" (email)"
echo "    Usage: input \"@Where=Paris\" or input \"@Email=test@example.com\""
echo "  Copy formats directly from recon output for best results"
echo ""
echo "Chaining with +:"
echo "  click \"[@Submit](#btn)\" + wait + recon"
echo "  click \"[@Close](#btn)\" + wait \"[role=dialog]\" --gone + recon"
echo "  input \"@Search=tokyo\" + wait \"[role=listbox]\" + recon"
echo ""
echo "Key Principles:"
echo "  1. URL params first - always prefer direct URLs over clicking"
echo "     Example: open \"https://airbnb.com/s/Paris?checkin=2025-12-20&checkout=2025-12-27\""
echo "  2. Use chrome tool commands - avoid chrome-cli execute unless truly needed"
echo "  3. Recon first - understand page before interacting"
echo "  4. Chain with + - action + wait + recon in one call"
echo "  5. Wait for specific element - not just any DOM change"
echo "  6. Use --gone when expecting element to disappear"
echo "  7. Filter recon with grep/awk - recon | awk '/^## Main(\$|:)/,/^## [^M]/'"
echo ""
echo "Raw chrome-cli:"
echo "  list tabs | info | open URL | activate -t ID | execute JS"
