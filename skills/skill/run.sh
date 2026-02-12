#!/bin/bash
#
# Skill manager - create, list, health check
#
# Usage:
#   run.sh new <name>      Create new skill with full scaffold
#   run.sh list            List all discovered skills
#   run.sh health [name]   Check skill follows conventions
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$(dirname "$SCRIPT_DIR")"
DATA_ROOT="$HOME/.claude-code/data"

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
info() { echo -e "  ${DIM}$*${NC}"; }

# ─────────────────────────────────────────────────────────────
# new - create new skill with full scaffold
# ─────────────────────────────────────────────────────────────
cmd_new() {
    local name="$1"

    if [[ -z "$name" ]]; then
        echo "Usage: $0 new <name>"
        exit 1
    fi

    local skill_dir="$SKILLS_DIR/$name"
    local data_dir="$DATA_ROOT/$name"

    if [[ -d "$skill_dir" ]]; then
        err "Skill already exists: $skill_dir"
        exit 1
    fi

    echo -e "${BLUE}Creating skill:${NC} $name"

    # Create all directories
    mkdir -p "$skill_dir"/{scripts,prompts,templates,watch,hooks,lib}
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
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  TODO: Add commands"
        ;;
esac
EOF
    chmod +x "$skill_dir/run.sh"
    ok "Created run.sh"

    # Create .gitignore
    echo "data" > "$skill_dir/.gitignore"
    ok "Created .gitignore"

    # Create empty watch yaml
    cat > "$skill_dir/watch/.gitkeep" << EOF
# Add watcher yaml files here
# Example: main.yaml
EOF
    ok "Created watch/"

    echo ""
    echo -e "${GREEN}Skill created:${NC} $skill_dir"
    echo ""
    echo "Structure:"
    ls -la "$skill_dir" | tail -n +2 | sed 's/^/  /'
}

# ─────────────────────────────────────────────────────────────
# list - discover and list all skills
# ─────────────────────────────────────────────────────────────
cmd_list() {
    echo -e "${BLUE}Skills:${NC}"
    echo ""

    local count=0
    for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
        [[ -f "$skill_md" ]] || continue

        local skill_dir=$(dirname "$skill_md")
        local name=$(basename "$skill_dir")

        # Parse description from frontmatter
        local desc=$(grep "^description:" "$skill_md" 2>/dev/null | sed 's/description:[[:space:]]*//' | head -1)
        [[ -z "$desc" ]] && desc="${DIM}(no description)${NC}"

        # Check for components
        local components=""
        [[ -f "$skill_dir/run.sh" ]] && components+="run "
        [[ -d "$skill_dir/watch" && -n "$(ls -A "$skill_dir/watch" 2>/dev/null | grep -v gitkeep)" ]] && components+="watch "
        [[ -d "$skill_dir/hooks" && -n "$(ls -A "$skill_dir/hooks" 2>/dev/null)" ]] && components+="hooks "
        [[ -L "$skill_dir/data" ]] && components+="data "

        printf "  ${GREEN}%-15s${NC} %s\n" "$name" "$desc"
        [[ -n "$components" ]] && printf "  ${DIM}%-15s [%s]${NC}\n" "" "${components% }"

        ((count++))
    done

    echo ""
    echo -e "${DIM}Total: $count skills${NC}"
}

# ─────────────────────────────────────────────────────────────
# health - verify skill follows conventions
# ─────────────────────────────────────────────────────────────
cmd_health() {
    local name="${1:-}"
    local exit_code=0

    if [[ -n "$name" ]]; then
        check_skill "$name" || exit_code=1
    else
        # Check all skills
        for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
            [[ -f "$skill_md" ]] || continue
            local skill_name=$(basename "$(dirname "$skill_md")")
            check_skill "$skill_name" || exit_code=1
            echo ""
        done
    fi

    return $exit_code
}

check_skill() {
    local name="$1"
    local skill_dir="$SKILLS_DIR/$name"
    local issues=0

    echo -e "${BLUE}$name${NC}"

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
# Main
# ─────────────────────────────────────────────────────────────
case "${1:-}" in
    new)
        cmd_new "${2:-}"
        ;;
    list)
        cmd_list
        ;;
    health)
        cmd_health "${2:-}"
        ;;
    *)
        echo "Skill manager"
        echo ""
        echo "Usage:"
        echo "  $0 new <name>      Create new skill with full scaffold"
        echo "  $0 list            List all discovered skills"
        echo "  $0 health [name]   Check skill follows conventions"
        ;;
esac
