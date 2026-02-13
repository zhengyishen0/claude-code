#!/bin/bash
#
# Agent - unified interface for AI coding agents
#
# Usage:
#   agent "prompt"              # Claude Code (default)
#   agent -r                    # Resume session picker
#   agent -P <profile> "prompt" # Use named profile
#
set -euo pipefail
: "${ZENIX_ROOT:=$HOME/.zenix}"

# Default to claude-code
exec "$ZENIX_ROOT/skills/system/agent/scripts/claude-code.sh" "$@"
