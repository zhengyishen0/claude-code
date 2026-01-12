#!/usr/bin/env bash
# claude-tools/world/commands/event.sh
# Log an event to world.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLD_LOG="$SCRIPT_DIR/../world.log"

show_help() {
    cat <<'EOF'
event - Log an event to world.log

USAGE:
    event <source> <identifier> <output>

ARGUMENTS:
    source      Event source: chrome, bash, file, api, system, user
    identifier  What specifically (URL, command, file path, etc.)
    output      Free-form description of what happened

EXAMPLES:
    event chrome "airbnb.com/s/Paris" "clicked Search, 24 listings loaded"
    event bash "git-status" "clean working directory"
    event file "src/config.json" "modified"
    event api "api.stripe.com/charges" "200 OK, charge_id=ch_123"
    event system "abc123" "session started"
    event user "abc123" "captcha solved: boats"

FORMAT:
    [timestamp][event:source][identifier] output
EOF
}

# Check arguments
if [ $# -lt 3 ]; then
    show_help
    exit 1
fi

source="$1"
identifier="$2"
shift 2
output="$*"

# Validate source
valid_sources="chrome bash file api system user"
if ! echo "$valid_sources" | grep -qw "$source"; then
    echo "Invalid source: $source"
    echo "Valid sources: $valid_sources"
    exit 1
fi

# Ensure log exists
touch "$WORLD_LOG"

# Generate timestamp (ISO 8601 UTC)
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Write entry
entry="[$timestamp][event:$source][$identifier] $output"
echo "$entry" >> "$WORLD_LOG"

# Echo back for confirmation
echo "$entry"
