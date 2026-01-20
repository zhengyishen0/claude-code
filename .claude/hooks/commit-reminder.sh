#!/bin/bash
# Stop/SessionEnd/SubagentStop hook: Remind to commit if uncommitted changes exist

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../paths.sh"

# Debug: log that hook ran
echo "[$(date '+%Y-%m-%d %H:%M:%S')] commit-reminder.sh triggered" >> "$PROJECT_DIR/tmp/hook-debug.log"

# Check for uncommitted changes
if git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | grep -q .; then
    echo "" >&2
    echo "📍 Checkpoint. Uncommitted changes detected. Commit if you've reached a milestone." >&2
    echo "" >&2
    exit 1  # Warning - show message but don't block
fi

exit 0
