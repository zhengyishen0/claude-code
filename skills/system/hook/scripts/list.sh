#!/bin/bash
# List all registered hooks across skills
set -euo pipefail

ZENIX_ROOT="${ZENIX_ROOT:-$HOME/.zenix}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
GRAY='\033[0;90m'
NC='\033[0m'

# Parse arguments
FILTER_EVENT=""
FILTER_SKILL=""
OUTPUT_FORMAT="table"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --event|-e)
            FILTER_EVENT="$2"
            shift 2
            ;;
        --skill|-s)
            FILTER_SKILL="$2"
            shift 2
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        *)
            # Positional: could be event or skill filter
            if [[ -z "$FILTER_EVENT" ]]; then
                FILTER_EVENT="$1"
            fi
            shift
            ;;
    esac
done

# Collect all hooks
collect_hooks() {
    for yaml_file in "$ZENIX_ROOT"/skills/*/*/hooks/settings.yaml; do
        [ -f "$yaml_file" ] || continue

        SKILL_DIR=$(dirname "$(dirname "$yaml_file")")
        SKILL_NAME=$(basename "$SKILL_DIR")
        CATEGORY=$(basename "$(dirname "$SKILL_DIR")")

        # Parse YAML
        if command -v yq &>/dev/null; then
            yq -o=json '.' "$yaml_file" 2>/dev/null | jq -c \
                --arg skill "$SKILL_NAME" \
                --arg category "$CATEGORY" \
                '.[] | . + {skill: $skill, category: $category}'
        else
            python3 -c "
import yaml, json, sys
with open('$yaml_file') as f:
    data = yaml.safe_load(f) or []
for entry in data:
    entry['skill'] = '$SKILL_NAME'
    entry['category'] = '$CATEGORY'
    print(json.dumps(entry))
" 2>/dev/null || true
        fi
    done
}

# Filter hooks
filter_hooks() {
    local hooks="$1"

    if [[ -n "$FILTER_EVENT" ]]; then
        hooks=$(echo "$hooks" | jq -c "select(.event | test(\"$FILTER_EVENT\"; \"i\"))")
    fi

    if [[ -n "$FILTER_SKILL" ]]; then
        hooks=$(echo "$hooks" | jq -c "select(.skill | test(\"$FILTER_SKILL\"; \"i\"))")
    fi

    echo "$hooks"
}

# Output as table
output_table() {
    local current_event=""

    while IFS= read -r line; do
        [ -z "$line" ] && continue

        event=$(echo "$line" | jq -r '.event')
        skill=$(echo "$line" | jq -r '.skill')
        category=$(echo "$line" | jq -r '.category')
        script=$(echo "$line" | jq -r '.script')
        matcher=$(echo "$line" | jq -r '.matcher // ""')
        timeout=$(echo "$line" | jq -r '.timeout // ""')
        description=$(echo "$line" | jq -r '.description // ""')

        # Print event header when it changes
        if [[ "$event" != "$current_event" ]]; then
            [[ -n "$current_event" ]] && echo ""
            echo -e "${BLUE}[$event]${NC}"
            current_event="$event"
        fi

        # Build info line
        info="${GREEN}${category}/${skill}${NC}"
        info+="${GRAY}/${NC}${script}"

        # Add matcher if present
        if [[ -n "$matcher" ]]; then
            info+=" ${GRAY}(${matcher})${NC}"
        fi

        # Add timeout if present
        if [[ -n "$timeout" ]]; then
            info+=" ${YELLOW}[${timeout}s]${NC}"
        fi

        echo -e "  $info"

        # Print description if present
        if [[ -n "$description" ]]; then
            echo -e "    ${GRAY}${description}${NC}"
        fi

    done
}

# Output as JSON
output_json() {
    jq -s '.'
}

# Main
hooks=$(collect_hooks)
hooks=$(filter_hooks "$hooks")

if [[ -z "$hooks" ]]; then
    echo "No hooks found."
    exit 0
fi

# Sort by event, then by skill
sorted=$(echo "$hooks" | jq -s 'sort_by(.event, .category, .skill)[]' -c)

case "$OUTPUT_FORMAT" in
    json)
        echo "$sorted" | output_json
        ;;
    *)
        echo "$sorted" | output_table
        echo ""
        echo -e "${GRAY}Use 'zenix hook list --event <name>' to filter by event${NC}"
        ;;
esac
