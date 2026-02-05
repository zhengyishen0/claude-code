#!/bin/bash
# Memory hint - auto-extract keywords from natural language and search
# Used by session start hooks to provide context hints
#
# Usage:
#   memory hint "help me debug the feishu approval workflow"
#   memory hint "帮我看看飞书审批的问题"
#
# Output: Session headers only (no message snippets)
#   [session-id] keyword1[count] keyword2[count] (N matches | date | project)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
  cat << 'EOF'
memory hint - Auto-extract keywords and search for relevant sessions

USAGE
  memory hint "<natural language query>"

DESCRIPTION
  Extracts keywords from natural language (English, Chinese, or mixed)
  and searches memory for relevant sessions. Returns session headers only,
  suitable for quick context hints.

EXAMPLES
  memory hint "help me debug the browser automation"
  memory hint "飞书审批流程有问题"
  memory hint "feishu API 调用失败"

OUTPUT FORMAT
  [session-id] keyword1[N] keyword2[M] (X matches | date | project)

EOF
}

if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  show_help
  exit 0
fi

TEXT="$*"

# Extract keywords using hint_keywords.py
KEYWORDS=$(python3 "$SCRIPT_DIR/hint_keywords.py" "$TEXT" 2>/dev/null)

if [ -z "$KEYWORDS" ]; then
  # No keywords extracted, nothing to search
  exit 0
fi

# Search with messages=0 for headers only, sessions=5 for quick results
# Use grep -v to remove the footer lines (macOS head doesn't support negative counts)
"$SCRIPT_DIR/search.sh" "$KEYWORDS" --messages 0 --sessions 5 2>/dev/null | grep -v "^Found matches\|^Tip:\|^$"
