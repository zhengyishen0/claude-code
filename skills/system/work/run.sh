#!/usr/bin/env bash
# work — agent workspace management with jj
set -euo pipefail

case "${1:-}" in
    on|start) shift; "$ZENIX_ROOT/skills/system/work/scripts/work-on.sh" "$@" ;;
    done|end) shift; "$ZENIX_ROOT/skills/system/work/scripts/work-done.sh" "$@" ;;
    drop)     shift; "$ZENIX_ROOT/skills/system/work/scripts/work-drop.sh" "$@" ;;
    clean)    shift; "$ZENIX_ROOT/skills/system/work/scripts/work-clean.sh" "$@" ;;
    *)
        echo "Usage: work <on|done|drop|clean> [args]"
        echo "  on \"task\"        Create workspace (use: cd \"\$(work on 'task')\")"
        echo "  done [\"summary\"]  Merge to main and cleanup"
        echo "  drop              Abandon workspace without merging"
        echo "  clean [-y]        Detect orphans, clean empty leaf"
        exit 1
        ;;
esac
