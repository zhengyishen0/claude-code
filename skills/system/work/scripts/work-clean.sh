#!/usr/bin/env bash
# work clean - Detect and clean orphan commits
# Usage: work clean [--safe | --space]
#   (no args)  Show what would be cleaned (dry run)
#   --safe     Clean empty orphan leaves WITHOUT workspace @
#   --space    Clean empty workspace @ leaves (not default@)
set -euo pipefail

mode="${1:-}"

# [PROTECTED] commits (never touch)
protected='description(substring:"[PROTECTED] do not edit")'
# Safe: empty orphan leaves without any workspace @
safe_revset="(heads(all()) & empty() & ~::bookmarks()) ~ working_copies() ~ ($protected)"
# Space: empty workspace leaves that are NOT [PROTECTED] and NOT direct children of main
# (children of main after push is expected state, not something to clean)
space_revset="heads(all()) & empty() & working_copies() ~ ($protected) ~ children(bookmarks())"
# Other: orphans that are not empty leaves, excluding [PROTECTED]
other_revset="((~::bookmarks()) ~ (heads(all()) & empty())) ~ ($protected)"

count_revset() {
    jj log -r "$1" --no-graph -T '"x"' 2>/dev/null | wc -c | tr -d '[:space:]'
}

show_revset() {
    local label="$1" revset="$2" hint="$3"
    local count=$(count_revset "$revset")
    : "${count:=0}"
    if [[ "$count" -gt 0 ]]; then
        echo "── $label ($count) ── [$hint]"
        jj log -r "$revset" --no-graph
        echo ""
    fi
}

# Count categories
safe_count=$(count_revset "$safe_revset")
space_count=$(count_revset "$space_revset")
other_count=$(count_revset "$other_revset")
: "${safe_count:=0}" "${space_count:=0}" "${other_count:=0}"

total=$((safe_count + space_count + other_count))

if [[ "$total" -eq 0 ]]; then
    echo "Your work is clean"
    exit 0
fi

case "$mode" in
    --safe)
        if [[ "$safe_count" -gt 0 ]]; then
            jj abandon -r "$safe_revset"
            echo "Cleaned $safe_count empty orphan(s)"
        else
            echo "Nothing to clean with --safe"
        fi
        ;;
    --space)
        if [[ "$space_count" -gt 0 ]]; then
            # Get list of workspace names and commit IDs that will be affected
            workspaces=$(jj log -r "$space_revset" --no-graph -T 'if(working_copies, working_copies ++ "\n", "")' 2>/dev/null | grep -v '^$' | sort -u)
            commit_ids=$(jj log -r "$space_revset" --no-graph -T 'commit_id ++ "\n"' 2>/dev/null | grep -v '^$')

            # Forget each workspace (removes from jj, keeps directory)
            for ws in $workspaces; do
                ws_name="${ws%@}"  # Remove trailing @
                if [[ "$ws_name" != "default" ]]; then
                    jj workspace forget "$ws_name" 2>/dev/null || true
                fi
            done

            # Abandon the orphaned commits
            for commit_id in $commit_ids; do
                jj abandon "$commit_id" 2>/dev/null || true
            done

            echo "Cleaned $space_count workspace(s) - use 'work on' to reattach"
        else
            echo "Nothing to clean with --space"
        fi
        ;;
    "")
        # Dry run - show what would be cleaned
        echo "Cleanable commits: $total"
        echo ""
        show_revset "Safe" "$safe_revset" "--safe"
        show_revset "Workspace" "$space_revset" "--space"
        show_revset "Other" "$other_revset" "manual: jj abandon or jj rebase"
        ;;
    *)
        echo "Usage: work clean [--safe | --space]" >&2
        exit 1
        ;;
esac
