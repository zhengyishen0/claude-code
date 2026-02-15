#!/bin/bash
#
# zenix convert - Convert a skill directory to a git submodule
#
# Usage:
#   zenix convert <category/skill> [github-user]
#
# Example:
#   zenix convert core/memory
#   zenix convert community/wechat zhengyishen0
#
# This script:
#   1. Creates a new GitHub repo (zenix-<skill>)
#   2. Copies skill contents and pushes to the new repo
#   3. Removes the directory and adds it as a submodule
#   4. Commits the change with git (not jj - they don't mix well with submodules)
#   5. Imports the change into jj
#
# IMPORTANT: jj and git submodules don't play well together.
# This script uses pure git for submodule operations, then imports to jj.
#

set -euo pipefail

# Determine paths (works both standalone and via zenix)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZENIX_DIR="${ZENIX_DIR:-$(dirname "$SCRIPT_DIR")}"
ZENIX_ROOT="${ZENIX_ROOT:-$(dirname "$(dirname "$(dirname "$ZENIX_DIR")")")}"
SKILLS_DIR="$ZENIX_ROOT/skills"
DATA_ROOT="$ZENIX_ROOT/data"

source "$ZENIX_DIR/lib/output.sh"

show_help() {
    echo "zenix convert - Convert a skill to a git submodule"
    echo ""
    echo "Usage:"
    echo "  zenix convert <category/skill> [github-user]"
    echo ""
    echo "Arguments:"
    echo "  category/skill   Path relative to skills/ (e.g., core/memory)"
    echo "  github-user      GitHub username (default: zhengyishen0)"
    echo ""
    echo "Example:"
    echo "  zenix convert core/browser"
    echo "  zenix convert community/wechat zhengyishen0"
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
main() {
    local skill_path="${1:-}"
    local github_user="${2:-zhengyishen0}"

    if [[ -z "$skill_path" ]] || [[ "$skill_path" == "-h" ]] || [[ "$skill_path" == "--help" ]]; then
        show_help
        exit 0
    fi

    # Parse path
    local full_path="$SKILLS_DIR/$skill_path"
    local skill_name=$(basename "$skill_path")
    local category=$(dirname "$skill_path")
    local repo_name="zenix-$skill_name"
    local repo_url="https://github.com/$github_user/$repo_name.git"

    # Validate
    if [[ ! -d "$full_path" ]]; then
        err "Skill not found: $full_path"
        exit 1
    fi

    if [[ ! -f "$full_path/SKILL.md" ]]; then
        err "Not a valid skill (missing SKILL.md): $full_path"
        exit 1
    fi

    # Check if already a submodule
    if git -C "$ZENIX_ROOT" ls-files --stage "$skill_path" 2>/dev/null | grep -q "^160000"; then
        err "Already a submodule: $skill_path"
        exit 1
    fi

    echo -e "${BLUE}Converting skill to submodule:${NC} $skill_path"
    echo "  Repo: $repo_url"
    echo ""

    # Step 1: Create GitHub repo
    echo -e "${BLUE}[1/6]${NC} Creating GitHub repo..."
    if gh repo view "$github_user/$repo_name" &>/dev/null; then
        warn "Repo already exists: $github_user/$repo_name"
    else
        gh repo create "$repo_name" --public --description "Zenix skill: $skill_name"
        ok "Created repo: $github_user/$repo_name"
    fi

    # Step 2: Copy to temp and initialize git
    echo -e "${BLUE}[2/6]${NC} Preparing skill contents..."
    local tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    # Copy contents (excluding data symlink)
    rsync -a --exclude='data' "$full_path/" "$tmp_dir/"

    # Initialize git and push
    cd "$tmp_dir"
    git init -q
    git add -A
    git commit -q -m "Initial commit: $skill_name skill"
    git branch -M main
    git remote add origin "$repo_url"
    git push -u origin main -f
    ok "Pushed to $repo_url"

    # Step 3: Remove directory from git
    echo -e "${BLUE}[3/6]${NC} Removing original directory..."
    cd "$ZENIX_ROOT"
    git rm -rf "skills/$skill_path"
    ok "Removed skills/$skill_path"

    # Step 4: Add as submodule
    echo -e "${BLUE}[4/6]${NC} Adding as submodule..."
    git submodule add "$repo_url" "skills/$skill_path"
    ok "Added submodule"

    # Step 5: Commit with git
    echo -e "${BLUE}[5/6]${NC} Committing change..."
    git commit -m "Convert $skill_name to submodule

Repo: $repo_url"
    ok "Committed"

    # Step 6: Import to jj
    echo -e "${BLUE}[6/6]${NC} Importing to jj..."
    jj git import
    ok "Imported to jj"

    # Recreate data symlink if data directory exists
    local data_dir="$DATA_ROOT/$skill_name"
    if [[ -d "$data_dir" ]]; then
        ln -sf "$data_dir" "$full_path/data"
        ok "Recreated data symlink"
    fi

    # Run npm install if package.json exists
    if [[ -f "$full_path/package.json" ]]; then
        echo ""
        echo -e "${BLUE}Running npm install...${NC}"
        cd "$full_path" && npm install
        ok "Dependencies installed"
    fi

    echo ""
    echo -e "${GREEN}Done!${NC} Skill converted to submodule."
    echo ""
    echo "Next steps:"
    echo "  - Verify with: git submodule status"
    echo "  - Push main repo: jj git push"
}

main "$@"
