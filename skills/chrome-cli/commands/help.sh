#!/bin/bash
# help.sh - Show help (dynamically assembled from commands)
# Usage: help.sh

CMD_DIR="$(dirname "$0")"

echo "chrome-cli-plus - Enhanced chrome-cli with React/SPA support"
echo ""
echo "Commands:"
for cmd in recon open wait click input esc tabs info close; do
  "$CMD_DIR/$cmd.sh" --help | sed 's/^/  /'
done
echo ""
echo "Key Principles:"
echo "  1. Recon first - understand page before interacting"
echo "  2. Wait after actions - use wait after clicks/navigation"
echo "  3. Re-run recon - verify state changes after actions"
echo "  4. URL params > clicking - faster and more reliable"
echo "  5. Keep window clean - close unused tabs before opening"
echo "  6. JS returns strings - chrome-cli crashes otherwise"
echo ""
echo "Raw chrome-cli:"
echo "  list tabs | info | open URL | activate -t ID | execute JS"
