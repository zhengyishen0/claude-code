#!/usr/bin/env bash
# protected.sh - [PROTECTED] buffer management
# Source this file: source "$(dirname "$0")/../lib/protected.sh"

# Get the change ID of [PROTECTED] commit (empty if not found)
get_protected_rev() {
    jj log -r 'all()' --no-graph -T 'if(description.starts_with("[PROTECTED]"), change_id.short(), "")' 2>/dev/null | head -1
}

# Check if current @ is [PROTECTED]
is_protected() {
    local msg=$(jj log -r @ --no-graph -T 'description' 2>/dev/null)
    [[ "$msg" == "[PROTECTED]"* ]]
}

# Ensure [PROTECTED] exists, is a leaf of main, and default@ points to it
# Call this from any work command to guarantee correct state
ensure_protected() {
    local repo_root="${1:-$(jj root 2>/dev/null || pwd)}"
    cd "$repo_root"

    local protected_rev=$(get_protected_rev)

    # 1. Create if missing
    if [[ -z "$protected_rev" ]]; then
        echo "Creating [PROTECTED] buffer..." >&2
        jj new main -m "[PROTECTED] do not edit — use \`work on\`"
        protected_rev=$(jj log -r @ --no-graph -T 'change_id.short()')
    else
        # 2. Ensure it's a child of main (rebase if not)
        local parent=$(jj log -r "${protected_rev}-" --no-graph -T 'change_id.short()' 2>/dev/null || echo "")
        local main_rev=$(jj log -r main --no-graph -T 'change_id.short()' 2>/dev/null || echo "")

        if [[ "$parent" != "$main_rev" ]]; then
            echo "Rebasing [PROTECTED] to main..." >&2
            jj rebase -r "$protected_rev" -d main 2>/dev/null || true
        fi
    fi

    # 3. Ensure default@ points to PROTECTED
    local default_at=$(jj workspace list 2>/dev/null | grep "^default:" | awk '{print $2}')

    if [[ "$default_at" != "$protected_rev" ]]; then
        # Move default@ to PROTECTED
        jj edit "$protected_rev" 2>/dev/null || true
    fi
}
