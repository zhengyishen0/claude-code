#!/bin/bash
# Browser cleanup hook - runs at session start
# Cleans up stale browser port registry entries

BROWSER_DATA_DIR="$CLAUDE_PROJECT_DIR/browser/data"
PORT_REGISTRY="$BROWSER_DATA_DIR/port-registry"

# Exit if registry doesn't exist
if [ ! -f "$PORT_REGISTRY" ]; then
  exit 0
fi

# Read registry and check each entry
cleaned=0
valid_entries=""

while IFS=: read -r session port pid startTime mode; do
  # Skip empty lines
  [ -z "$session" ] && continue

  # Check if process is still running
  if kill -0 "$pid" 2>/dev/null; then
    # Process alive, keep entry
    valid_entries="${valid_entries}${session}:${port}:${pid}:${startTime}:${mode}\n"
  else
    # Process dead, skip entry (cleanup)
    cleaned=$((cleaned + 1))
  fi
done < "$PORT_REGISTRY"

# Write back valid entries
if [ $cleaned -gt 0 ]; then
  printf "$valid_entries" > "$PORT_REGISTRY"
  echo "Browser cleanup: removed $cleaned stale session(s)"
fi

exit 0
