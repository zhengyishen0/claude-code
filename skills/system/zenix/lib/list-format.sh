#!/bin/bash
#
# list-format.sh - Unified list formatter for zenix skills
#
# Input: TSV via stdin (group, name, tag, description)
#        Use empty string for no tag, not missing field
#
# Output: Formatted list matching zenix list style
#
# Usage:
#   printf '%s\t%s\t%s\t%s\n' "core" "browser" "" "Browser automation" | list-format.sh
#   printf '%s\t%s\t%s\t%s\n' "core" "daily" "info only" "Daily log" | list-format.sh
#   generate_data | list-format.sh --inline
#
# Styles:
#   --group   Group by first column with [group] headers (default)
#   --inline  Single list with inline [group] tags
#
# Can also be sourced:
#   source list-format.sh
#   generate_data | list_format --group

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
GRAY='\033[0;90m'
NC='\033[0m'

list_format() {
    local style="group"

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --group)  style="group"; shift ;;
            --inline) style="inline"; shift ;;
            *)        shift ;;
        esac
    done

    # Read stdin into temp file for multiple passes
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile"

    if [[ "$style" == "group" ]]; then
        _format_grouped "$tmpfile"
    else
        _format_inline "$tmpfile"
    fi

    rm -f "$tmpfile"
}

_format_grouped() {
    local file="$1"
    local current_group=""
    local first_group=true

    # Sort by group, then name and process with awk
    sort -t$'\t' -k1,1 -k2,2 "$file" | while IFS= read -r line; do
        local group name tag desc
        group=$(echo "$line" | cut -d$'\t' -f1)
        name=$(echo "$line" | cut -d$'\t' -f2)
        tag=$(echo "$line" | cut -d$'\t' -f3)
        desc=$(echo "$line" | cut -d$'\t' -f4-)

        [[ -z "$name" ]] && continue

        # New group header
        if [[ "$group" != "$current_group" ]]; then
            [[ "$first_group" == false ]] && echo ""
            echo -e "${BLUE}[${group}]${NC}"
            current_group="$group"
            first_group=false
        fi

        # Format: name (tag): description
        if [[ -n "$tag" ]]; then
            echo -e "${GREEN}${name}${NC} ${GRAY}(${tag})${NC}: ${desc}"
        else
            echo -e "${GREEN}${name}${NC}: ${desc}"
        fi
    done
}

_format_inline() {
    local file="$1"

    # Sort by name
    sort -t$'\t' -k2,2 "$file" | while IFS= read -r line; do
        local group name tag desc
        group=$(echo "$line" | cut -d$'\t' -f1)
        name=$(echo "$line" | cut -d$'\t' -f2)
        tag=$(echo "$line" | cut -d$'\t' -f3)
        desc=$(echo "$line" | cut -d$'\t' -f4-)

        [[ -z "$name" ]] && continue

        # Format: name [group] (tag): description
        if [[ -n "$tag" ]]; then
            echo -e "${GREEN}${name}${NC} ${BLUE}[${group}]${NC} ${GRAY}(${tag})${NC}: ${desc}"
        else
            echo -e "${GREEN}${name}${NC} ${BLUE}[${group}]${NC}: ${desc}"
        fi
    done
}

# If run directly (not sourced), execute with args
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    list_format "$@"
fi
