#!/bin/bash
# Journal hook: SessionEnd
# Reminds AI to note session end

# Read session info from stdin
read -r INPUT
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null | cut -c1-8)
REASON=$(echo "$INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null)

cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionEnd",
    "message": "JOURNAL: Session [$SESSION_ID] ending ($REASON). If significant work was done, append summary to vault/daily/$(date +%Y-%m-%d).md"
  }
}
EOF
