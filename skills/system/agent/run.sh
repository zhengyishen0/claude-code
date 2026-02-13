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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Default to claude-code
exec "$SCRIPT_DIR/scripts/claude-code.sh" "$@"
