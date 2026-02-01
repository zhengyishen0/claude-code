#!/bin/bash
# PreToolUse hook: Warn about unstaged changes
# DISABLED for jj - no staging concept
#
# Kept for git fallback mode

set -eo pipefail

# Skip if using jj - no staging concept
if jj root &>/dev/null; then
    exit 0
fi

# Original git logic in .bak file if needed
exit 0
