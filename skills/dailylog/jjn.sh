#!/bin/bash
# jjn - jj new with daily log sync
#
# Usage: jjn "commit message"
#        jjn "[tag] commit message"
#
# This creates a new jj commit and logs it to the daily log.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAILYLOG="$SCRIPT_DIR/dailylog.py"

if [ -z "$1" ]; then
    echo "Usage: jjn \"commit message\""
    echo "       jjn \"[tag] commit message\""
    exit 1
fi

MESSAGE="$1"

# Extract tag if present (e.g., "[decision] message" -> tag=decision, msg=message)
TAG=""
MSG="$MESSAGE"
if [[ "$MESSAGE" =~ ^\[([^\]]+)\]\ (.+)$ ]]; then
    TAG="${BASH_REMATCH[1]}"
    MSG="${BASH_REMATCH[2]}"
fi

# Describe current change and create new working copy (jj commit = describe + new)
jj commit -m "$MESSAGE"

# Get the change ID of the committed change (now the parent)
CHANGE_ID=$(jj log -r @- --no-graph -T 'change_id.short()')

# Log to daily log
python3 "$DAILYLOG" jj "$CHANGE_ID" "$MSG" ${TAG:+-t "$TAG"}

echo "Created commit $CHANGE_ID and logged to daily log"
