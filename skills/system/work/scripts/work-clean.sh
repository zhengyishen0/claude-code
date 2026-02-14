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
# Space: empty workspace leaves that are NOT [PROTECTED]
space_revset="heads(all()) & empty() & working_copies() ~ ($protected)"
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
            jj abandon -r "$space_revset"
            echo "Cleaned $space_count workspace leftover(s)"
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
