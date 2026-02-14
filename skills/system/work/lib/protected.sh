#!/usr/bin/env bash
# protected.sh - [PROTECTED] buffer management
# Source this file: source "$(dirname "$0")/../lib/protected.sh"

# Check if [PROTECTED] exists anywhere in repo
protected_exists() {
    local repo_root="${1:-$(jj root 2>/dev/null || pwd)}"
    cd "$repo_root"
    local found=$(jj log -r 'all()' --no-graph -T 'if(description.contains("[PROTECTED]"), "yes", "")' 2>/dev/null | head -1)
    [[ -n "$found" ]]
}

# Create [PROTECTED] at tip of main if not exists
ensure_protected() {
    local repo_root="${1:-$(jj root 2>/dev/null || pwd)}"
    cd "$repo_root"
    
    if protected_exists "$repo_root"; then
        return 0
    fi
    
    echo "Creating [PROTECTED] buffer..." >&2
    jj new main -m "[PROTECTED] do not edit — use \`work on\`"
    jj bookmark set main -r @
    echo "Created [PROTECTED] at main" >&2
}

# Check if current @ is [PROTECTED]
is_protected() {
    local msg=$(jj log -r @ --no-graph -T 'description' 2>/dev/null)
    [[ "$msg" == *"[PROTECTED]"* ]]
}

# Check if main is [PROTECTED]
main_is_protected() {
    local msg=$(jj log -r main --no-graph -T 'description' 2>/dev/null)
    [[ "$msg" == *"[PROTECTED]"* ]]
}
