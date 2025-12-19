#!/bin/bash
# Summarize search results using haiku model
# Input: search output via stdin
# Output: summarized sessions (one line per session)
set -eo pipefail

# Create temp files early for cleanup
INPUT_FILE=$(mktemp)
PROMPT_FILE=$(mktemp)
trap "rm -f $INPUT_FILE $PROMPT_FILE" EXIT

# Read input to file (avoids SIGPIPE with large input)
cat > "$INPUT_FILE"

# Check if claude is available
if ! command -v claude &>/dev/null; then
  echo "(claude CLI not found, showing raw results)" >&2
  cat "$INPUT_FILE"
  exit 0
fi

# Truncate to top 150 lines for summarization (from file, no pipe)
SUMMARY_INPUT=$(head -150 "$INPUT_FILE")

# Write prompt to temp file (avoids command line length limits)
cat > "$PROMPT_FILE" << 'EOF'
Summarize each session log below. Include: main topic, key files/functions mentioned, specific solutions or fixes. Format: SESSION_ID: [topic] - [key details]. One line per session. Output ONLY summaries, nothing else.

EOF
echo "$SUMMARY_INPUT" >> "$PROMPT_FILE"

# Call haiku with --tools "" to disable tools (pure text completion)
# Use cat to pipe the prompt to claude
SUMMARY=$(https_proxy=http://127.0.0.1:33210 http_proxy=http://127.0.0.1:33210 \
  cat "$PROMPT_FILE" | claude --model haiku --tools "" -p 2>&1)

# Check if summary succeeded (look for session ID pattern)
if echo "$SUMMARY" | grep -qE "^[a-f0-9-]{8,}"; then
  echo "$SUMMARY"
else
  # Fallback to raw output
  echo "(Summarization failed, showing raw results)" >&2
  cat "$INPUT_FILE"
fi
