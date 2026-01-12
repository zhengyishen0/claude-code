#!/usr/bin/env bash
# claude-tools/world/commands/check.sh
# Read new entries since last marker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLD_LOG="$SCRIPT_DIR/../world.log"
MARKER_LINE="=================READ-MARKER================="

show_help() {
    cat <<'EOF'
check - Read new entries since last marker

USAGE:
    check [agent-id]

ARGUMENTS:
    agent-id    Optional identifier for who is reading (for audit trail)

BEHAVIOR:
    1. Returns all entries after the last READ-MARKER
    2. Adds audit entry: "[timestamp][event:system][agent-id] checked N entries"
    3. Adds new READ-MARKER at end

EXAMPLES:
    check                    # Anonymous check
    check manager-xyz        # Check as specific agent
    check level2-supervisor  # Check as Level 2 supervisor

OUTPUT:
    New entries since last marker, or "no new entries"
EOF
}

if [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    show_help
    exit 0
fi

agent_id="${1:-anonymous}"

# Ensure log exists with initial marker
if [ ! -f "$WORLD_LOG" ]; then
    touch "$WORLD_LOG"
    echo "$MARKER_LINE" >> "$WORLD_LOG"
fi

# Find last marker line number
marker_line_num=$(grep -n "^$MARKER_LINE$" "$WORLD_LOG" | tail -1 | cut -d: -f1 || echo "0")

if [ "$marker_line_num" = "0" ]; then
    # No marker found, add one at end
    echo "$MARKER_LINE" >> "$WORLD_LOG"
    marker_line_num=$(wc -l < "$WORLD_LOG" | tr -d ' ')
fi

# Get total lines
total_lines=$(wc -l < "$WORLD_LOG" | tr -d ' ')
lines_after_marker=$((total_lines - marker_line_num))

# Read entries after marker
entry_count=0
new_entries=""

if [ "$lines_after_marker" -gt 0 ]; then
    new_entries=$(tail -n "$lines_after_marker" "$WORLD_LOG")
    # Count non-empty lines
    entry_count=$(echo "$new_entries" | grep -c '.' || echo "0")
fi

# Generate timestamp
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Add audit entry
echo "[$timestamp][event:system][$agent_id] checked $entry_count entries" >> "$WORLD_LOG"

# Add new marker
echo "$MARKER_LINE" >> "$WORLD_LOG"

# Output
if [ "$entry_count" -eq 0 ]; then
    echo "no new entries"
else
    echo "$new_entries"
fi
