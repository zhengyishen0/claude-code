#!/usr/bin/env bash
# work clean - Remove empty leaf orphan commits
# Usage: work clean
set -euo pipefail

# Find empty leaf orphans: heads that are empty and not ancestors of any bookmark
revset='heads(all()) & empty() & ~::bookmarks()'

commits=$(jj log -r "$revset" --no-graph -T 'change_id.short() ++ "\n"' 2>/dev/null | grep -v '^$' || true)

if [ -z "$commits" ]; then
    echo "No empty leaf orphans to clean"
    exit 0
fi

count=$(echo "$commits" | wc -l | tr -d ' ')
echo "Found $count empty leaf orphan(s):"
jj log -r "$revset" --no-graph

echo ""
read -p "Abandon these commits? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    jj abandon -r "$revset"
    echo "Cleaned up $count commit(s)"
else
    echo "Aborted"
fi
