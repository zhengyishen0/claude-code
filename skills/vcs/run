#!/usr/bin/env bash
# vcs — version control + agent workspace management
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
    on|start) shift; "$SCRIPT_DIR/scripts/work-on.sh" "$@" ;;
    done|end) shift; "$SCRIPT_DIR/scripts/work-done.sh" "$@" ;;
    *)
        echo "Usage: vcs <on|done> [args]"
        echo "  on \"task\"       Create workspace (uses CLAUDE_SESSION_ID or random)"
        echo "  done [\"summary\"] Merge to main and cleanup"
        exit 1
        ;;
esac
