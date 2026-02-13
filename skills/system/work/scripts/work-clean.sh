#!/usr/bin/env bash
# work clean - Detect and clean orphan commits
# Usage: work clean [-y]
set -euo pipefail

auto_yes=false
[[ "${1:-}" == "-y" ]] && auto_yes=true

# Revsets
orphans='~::bookmarks()'
empty_leaf='heads(all()) & empty() & ~::bookmarks()'
other='(~::bookmarks()) ~ (heads(all()) & empty() & ~::bookmarks())'

# Count
empty_leaf_count=$(jj log -r "$empty_leaf" --no-graph -T 'change_id.short() ++ "\n"' 2>/dev/null | grep -c -v '^$' || echo 0)
other_count=$(jj log -r "$other" --no-graph -T 'change_id.short() ++ "\n"' 2>/dev/null | grep -c -v '^$' || echo 0)

if [[ "$empty_leaf_count" -eq 0 ]] && [[ "$other_count" -eq 0 ]]; then
    echo "No orphan commits"
    exit 0
fi

echo "Orphan commits detected:"
echo ""

if [[ "$empty_leaf_count" -gt 0 ]]; then
    echo "── Empty leaf ($empty_leaf_count) ── [auto-cleanable with -y]"
    jj log -r "$empty_leaf" --no-graph
    echo ""
fi

if [[ "$other_count" -gt 0 ]]; then
    echo "── Other ($other_count) ── [manual: jj abandon or jj rebase]"
    jj log -r "$other" --no-graph
    echo ""
fi

# Clean empty leaf orphans
if [[ "$empty_leaf_count" -gt 0 ]]; then
    if [[ "$auto_yes" == "true" ]]; then
        jj abandon -r "$empty_leaf"
        echo "Cleaned $empty_leaf_count empty leaf orphan(s)"
    else
        read -p "Clean empty leaf orphans? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            jj abandon -r "$empty_leaf"
            echo "Cleaned $empty_leaf_count empty leaf orphan(s)"
        fi
    fi
fi

# Exit with error if other orphans remain
if [[ "$other_count" -gt 0 ]]; then
    echo ""
    echo "Other orphans remain. Manual cleanup needed."
    exit 1
fi
