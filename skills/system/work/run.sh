#!/usr/bin/env bash
# work — agent workspace management with jj
set -euo pipefail
: "${ZENIX_ROOT:=$HOME/.zenix}"

case "${1:-}" in
    on|start) shift; "$ZENIX_ROOT/skills/system/work/scripts/work-on.sh" "$@" ;;
    done|end) shift; "$ZENIX_ROOT/skills/system/work/scripts/work-done.sh" "$@" ;;
    *)
        echo "Usage: work <on|done> [args]"
        echo "  on \"task\"       Create workspace, then cd to it"
        echo "  done [\"summary\"] Merge to main and cleanup"
        exit 1
        ;;
esac
