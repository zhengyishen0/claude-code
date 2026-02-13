#!/usr/bin/env bash
# work push - Push to remote after checking for orphans
# Usage: work push
set -euo pipefail

# Revsets for different orphan types
orphans='~::bookmarks()'
empty_leaf_orphans='heads(all()) & empty() & ~::bookmarks()'
other_orphans="($orphans) ~ ($empty_leaf_orphans)"

# Count orphans
empty_leaf_count=$(jj log -r "$empty_leaf_orphans" --no-graph -T 'change_id.short() ++ "\n"' 2>/dev/null | grep -c -v '^$' || echo 0)
other_count=$(jj log -r "$other_orphans" --no-graph -T 'change_id.short() ++ "\n"' 2>/dev/null | grep -c -v '^$' || echo 0)

if [[ "$empty_leaf_count" -gt 0 ]] || [[ "$other_count" -gt 0 ]]; then
    echo "Orphan commits detected:"
    echo ""

    if [[ "$empty_leaf_count" -gt 0 ]]; then
        echo "── Empty leaf orphans ($empty_leaf_count) ──"
        jj log -r "$empty_leaf_orphans" --no-graph
        echo ""
        echo "  → Run: work clean -y"
        echo ""
    fi

    if [[ "$other_count" -gt 0 ]]; then
        echo "── Other orphans ($other_count) ──"
        jj log -r "$other_orphans" --no-graph
        echo ""
        echo "  → Manual cleanup needed (jj abandon or jj rebase)"
        echo ""
    fi

    echo "Push aborted. Clean up orphans first."
    exit 1
fi

echo "No orphans. Pushing..."
jj git push "$@"
