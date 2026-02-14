#!/usr/bin/env bash
# protected.sh - [PROTECTED] buffer management
# Source this file: source "$(dirname "$0")/../lib/protected.sh"

# Check if [PROTECTED] exists anywhere in repo
protected_exists() {
    local repo_root="${1:-$(jj root 2>/dev/null || pwd)}"
    cd "$repo_root"
    local found=$(jj log -r 'all()' --no-graph -T 'if(description.starts_with("[PROTECTED]"), "yes", "")' 2>/dev/null | head -1)
    [[ -n "$found" ]]
}

# Get the revision ID of [PROTECTED] commit
get_protected_rev() {
    jj log -r 'all()' --no-graph -T 'if(description.starts_with("[PROTECTED]"), change_id.short(), "")' 2>/dev/null | head -1
}

# Create [PROTECTED] as child of main if not exists
ensure_protected() {
    local repo_root="${1:-$(jj root 2>/dev/null || pwd)}"
    cd "$repo_root"

    if protected_exists "$repo_root"; then
        return 0
    fi

    echo "Creating [PROTECTED] buffer..." >&2
    jj new main -m "[PROTECTED] do not edit — use \`work on\`"
    echo "Created [PROTECTED] as child of main" >&2
}

# Ensure default@ is on [PROTECTED] (rebase if needed, create if missing)
ensure_protected_for_default() {
    local repo_root="${1:-$(jj root 2>/dev/null || pwd)}"
    cd "$repo_root"

    local protected_rev=$(get_protected_rev)

    if [[ -n "$protected_rev" ]]; then
        # Rebase existing [PROTECTED] onto new main
        jj rebase -r "$protected_rev" -d main 2>/dev/null || true
    else
        # Create new [PROTECTED] as child of main
        jj new main -m "[PROTECTED] do not edit — use \`work on\`"
        protected_rev=$(jj log -r @ --no-graph -T 'change_id.short()')
    fi

    # Move default@ to [PROTECTED]
    jj workspace update-stale 2>/dev/null || true
    cd "$repo_root" && jj edit "$protected_rev" 2>/dev/null || true
}

# Check if current @ is [PROTECTED]
is_protected() {
    local msg=$(jj log -r @ --no-graph -T 'description' 2>/dev/null)
    [[ "$msg" == "[PROTECTED]"* ]]
}
