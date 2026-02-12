#!/bin/bash
# Journal hook: PreCompact
# Reminds AI to save context before compaction

# Read session info from stdin
read -r INPUT
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null | cut -c1-8)

cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "message": "JOURNAL REMINDER: Context is about to be compacted. Write a brief summary of this session to vault/journal/$(date +%Y-%m-%d).md under ## Sessions. Include session ID [$SESSION_ID] and key topics/decisions/outcomes. Use Edit tool to append."
  }
}
EOF
