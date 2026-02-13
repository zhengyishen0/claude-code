#!/bin/bash
# Append jj graph to today's daily log
# Run at end of day (manually or via cron)

set -e

ZENIX_ROOT="${ZENIX_ROOT:-$HOME/.zenix}"
VAULT_DIR="$ZENIX_ROOT/vault"
TODAY=$(date +%Y-%m-%d)
DAILY_FILE="$VAULT_DIR/daily/$TODAY.md"

# Ensure directory exists
mkdir -p "$VAULT_DIR/daily"

# Create file if doesn't exist
if [ ! -f "$DAILY_FILE" ]; then
    cat > "$DAILY_FILE" << EOF
# $TODAY

## Sessions

## JJ Graph
EOF
fi

# Get jj graph
JJ_GRAPH=$(jj log -r "::@" -n 15 2>/dev/null || echo "No jj repo")

# Check if JJ Graph section exists
if grep -q "## JJ Graph" "$DAILY_FILE"; then
    # Remove old JJ Graph section and everything after it
    sed -i '' '/^## JJ Graph/,$d' "$DAILY_FILE"
fi

# Append new JJ Graph section
cat >> "$DAILY_FILE" << EOF

## JJ Graph

\`\`\`
$JJ_GRAPH
\`\`\`
EOF

echo "Updated $DAILY_FILE"
