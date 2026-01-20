#!/bin/bash
# Stop/SessionEnd hook: Remind to commit if uncommitted changes exist

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../paths.sh"

# Check for uncommitted changes
if git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | grep -q .; then
    echo ""
    echo "📍 Checkpoint. Uncommitted changes detected. Commit if you've reached a milestone."
    echo ""
fi

exit 0
