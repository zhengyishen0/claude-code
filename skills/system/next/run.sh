#!/bin/bash
#
# next - Unified CLI dispatcher for zenix skills
#
# Usage:
#   next                    List available skills
#   next list               Same as above
#   next <skill> [args]     Run a skill
#   next create <name>      Create new skill in custom/
#   next doctor [name]      Validate skill conventions
#

set -euo pipefail

ZENIX_ROOT="${ZENIX_ROOT:-$HOME/.zenix}"
SKILLS_DIR="$ZENIX_ROOT/skills"
DATA_ROOT="$ZENIX_ROOT/data"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
DIM='\033[0;90m'
NC='\033[0m'

ok() { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }
err() { echo -e "  ${RED}✗${NC} $*"; }

# ─────────────────────────────────────────────────────────────
# list - show all available skills
# ─────────────────────────────────────────────────────────────
cmd_list() {
    local current_category=""

    for skill_md in "$SKILLS_DIR"/*/*/SKILL.md; do
        [[ -f "$skill_md" ]] || continue

        local skill_dir=$(dirname "$skill_md")
        local name=$(basename "$skill_dir")
        local category=$(basename "$(dirname "$skill_dir")")

        # Print category header when it changes
        if [[ "$category" != "$current_category" ]]; then
            [[ -n "$current_category" ]] && echo ""
            echo -e "${BLUE}[${category}]${NC}"
            current_category="$category"
        fi

        # Parse description from frontmatter
        local desc=$(grep "^description:" "$skill_md" 2>/dev/null | sed 's/description:[[:space:]]*//' | head -1)
        [[ -z "$desc" ]] && desc="(no description)"

        # Check if run.sh exists
        if [[ -x "$skill_dir/run.sh" ]]; then
            echo -e "${GREEN}${name}${NC}: $desc"
        else
            echo -e "${GREEN}${name}${NC} ${DIM}(info only)${NC}: $desc"
        fi
    done

    echo ""
    echo -e "${DIM}Use \`next <skill>\` to run a skill.${NC}"
}

# ─────────────────────────────────────────────────────────────
# create - create new skill with full scaffold (always in custom/)
# ─────────────────────────────────────────────────────────────
cmd_create() {
    local name="$1"

    if [[ -z "$name" ]]; then
        echo "Usage: next create <name>"
        exit 1
    fi

    # Reserved names
    case "$name" in
        list|create|doctor|help|-h|--help)
            err "Cannot create skill with reserved name: $name"
            exit 1
            ;;
    esac

    # Always create in custom/ category
    local category="custom"
    mkdir -p "$SKILLS_DIR/$category"

    local skill_dir="$SKILLS_DIR/$category/$name"
    local data_dir="$DATA_ROOT/$name"

    if [[ -d "$skill_dir" ]]; then
        err "Skill already exists: $skill_dir"
        exit 1
    fi

    echo -e "${BLUE}Creating skill:${NC} $name"

    # Create all directories
    mkdir -p "$skill_dir"/{scripts,prompts,templates,watch,hooks,lib,config}
    ok "Created directories"

    # Create data directory and symlink
    mkdir -p "$data_dir"
    ln -s "$data_dir" "$skill_dir/data"
    ok "Created data symlink → $data_dir"

    # Create SKILL.md
    cat > "$skill_dir/SKILL.md" << EOF
---
name: $name
description: TODO: Add description
---

# $name

TODO: Describe what this skill does.

## Usage

TODO: How to use this skill.
EOF
    ok "Created SKILL.md"

    # Create run.sh
    cat > "$skill_dir/run.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
    *)
        echo "Usage: next $SKILL_NAME <command>"
        echo ""
        echo "Commands:"
        echo "  TODO: Add commands"
        ;;
esac
EOF
    # Replace placeholder with actual skill name
    sed -i '' "s/\$SKILL_NAME/$name/" "$skill_dir/run.sh"
    chmod +x "$skill_dir/run.sh"
    ok "Created run.sh"

    # Create .gitignore
    echo "data" > "$skill_dir/.gitignore"
    ok "Created .gitignore"

    echo ""
    echo -e "${GREEN}Skill created:${NC} $skill_dir"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $skill_dir/SKILL.md"
    echo "  2. Edit $skill_dir/run.sh"
    echo "  3. Run: next $name"
}

# ─────────────────────────────────────────────────────────────
# doctor - verify skill follows conventions
# ─────────────────────────────────────────────────────────────
cmd_doctor() {
    local name="${1:-}"
    local exit_code=0

    if [[ -n "$name" ]]; then
        # Find skill by name
        local skill_dir=$(find "$SKILLS_DIR" -maxdepth 2 -type d -name "$name" | head -1)
        if [[ -z "$skill_dir" ]]; then
            err "Skill not found: $name"
            return 1
        fi
        check_skill "$skill_dir" || exit_code=1
    else
        # Check all skills
        for skill_md in "$SKILLS_DIR"/*/*/SKILL.md; do
            [[ -f "$skill_md" ]] || continue
            local skill_dir=$(dirname "$skill_md")
            check_skill "$skill_dir" || exit_code=1
            echo ""
        done
    fi

    return $exit_code
}

check_skill() {
    local skill_dir="$1"
    local name=$(basename "$skill_dir")
    local category=$(basename "$(dirname "$skill_dir")")
    local issues=0

    echo -e "${BLUE}[${category}/${name}]${NC}"

    # SKILL.md exists
    if [[ -f "$skill_dir/SKILL.md" ]]; then
        ok "SKILL.md"

        # Has frontmatter with name and description
        if head -1 "$skill_dir/SKILL.md" | grep -q "^---"; then
            if grep -q "^name:" "$skill_dir/SKILL.md" && grep -q "^description:" "$skill_dir/SKILL.md"; then
                ok "frontmatter (name, description)"
            else
                warn "frontmatter missing name or description"
                ((issues++))
            fi
        else
            warn "missing frontmatter"
            ((issues++))
        fi
    else
        err "SKILL.md missing"
        ((issues++))
    fi

    # run.sh is executable (if exists)
    if [[ -f "$skill_dir/run.sh" ]]; then
        if [[ -x "$skill_dir/run.sh" ]]; then
            ok "run.sh executable"
        else
            err "run.sh not executable"
            ((issues++))
        fi
    fi

    # watch/*.yaml have name and type (if any exist)
    if [[ -d "$skill_dir/watch" ]]; then
        for yaml in "$skill_dir/watch"/*.yaml; do
            [[ -f "$yaml" ]] || continue
            local yaml_name=$(basename "$yaml")

            if grep -q "^name:" "$yaml" && grep -q "^type:" "$yaml"; then
                ok "watch/$yaml_name"
            else
                err "watch/$yaml_name missing name or type"
                ((issues++))
            fi
        done
    fi

    # data symlink valid (if exists)
    if [[ -L "$skill_dir/data" ]]; then
        if [[ -d "$skill_dir/data" ]]; then
            ok "data symlink"
        else
            err "data symlink broken"
            ((issues++))
        fi
    fi

    # hooks are executable (if any exist)
    if [[ -d "$skill_dir/hooks" ]]; then
        for hook in "$skill_dir/hooks"/*.sh; do
            [[ -f "$hook" ]] || continue
            local hook_name=$(basename "$hook")

            if [[ -x "$hook" ]]; then
                ok "hooks/$hook_name"
            else
                err "hooks/$hook_name not executable"
                ((issues++))
            fi
        done
    fi

    # Summary
    if [[ $issues -gt 0 ]]; then
        echo -e "  ${RED}$issues issue(s)${NC}"
        return 1
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────
# route - find and execute a skill
# ─────────────────────────────────────────────────────────────
route_skill() {
    local skill_name="$1"
    shift

    # Find skill run.sh
    local run_sh=$(find "$SKILLS_DIR" -maxdepth 3 -path "*/$skill_name/run.sh" 2>/dev/null | head -1)

    if [[ -z "$run_sh" ]] || [[ ! -x "$run_sh" ]]; then
        # Check if skill exists but has no run.sh
        local skill_md=$(find "$SKILLS_DIR" -maxdepth 3 -path "*/$skill_name/SKILL.md" 2>/dev/null | head -1)
        if [[ -n "$skill_md" ]]; then
            err "'$skill_name' is info-only (no run.sh)"
            echo ""
            echo "View documentation:"
            echo "  cat $(dirname "$skill_md")/SKILL.md"
        else
            err "Skill not found: $skill_name"
            echo ""
            echo "Run 'next' to see available skills."
        fi
        exit 1
    fi

    exec "$run_sh" "$@"
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
case "${1:-}" in
    ""|list)
        cmd_list
        ;;
    create)
        cmd_create "${2:-}"
        ;;
    doctor)
        cmd_doctor "${2:-}"
        ;;
    -h|--help)
        echo "next - Unified CLI dispatcher for zenix skills"
        echo ""
        echo "Usage:"
        echo "  next                    List available skills"
        echo "  next list               Same as above"
        echo "  next <skill> [args]     Run a skill"
        echo "  next create <name>      Create new skill in custom/"
        echo "  next doctor [name]      Validate skill conventions"
        ;;
    *)
        route_skill "$@"
        ;;
esac
