#!/bin/bash
# PostToolUse hook: Run diagnostics on edited files
# Warns about errors but doesn't block (exit 0)
#
# Triggered after Edit/Write tool calls

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIAGNOSE="$SCRIPT_DIR/../../diagnose/diagnose"

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')

# Skip if no file path
[[ -z "$file_path" ]] && exit 0

# Skip if file doesn't exist (was deleted)
[[ ! -f "$file_path" ]] && exit 0

# Detect language
detect_language() {
    local file="$1"
    case "$file" in
        *.sh|*.bash) echo "shell" ;;
        *.py) echo "python" ;;
        *.js|*.jsx) echo "javascript" ;;
        *.ts|*.tsx) echo "typescript" ;;
        *.go) echo "go" ;;
        *.json) echo "json" ;;
        *.yaml|*.yml) echo "yaml" ;;
        *.c|*.h) echo "c" ;;
        *.cpp|*.cc|*.cxx|*.hpp|*.hxx) echo "cpp" ;;
        *.md|*.markdown) echo "markdown" ;;
        *) echo "" ;;
    esac
}

lang=$(detect_language "$file_path")

# Skip unsupported file types
[[ -z "$lang" ]] && exit 0

# Run per-file diagnostic
run_diagnostic() {
    local file="$1"
    local lang="$2"

    case "$lang" in
        shell)
            command -v shellcheck &>/dev/null || return 0
            shellcheck "$file" 2>&1
            ;;
        python)
            command -v ruff &>/dev/null || return 0
            ruff check "$file" 2>&1
            ;;
        javascript|typescript)
            command -v eslint &>/dev/null || return 0
            eslint "$file" 2>&1
            ;;
        go)
            command -v go &>/dev/null || return 0
            go vet "$file" 2>&1
            ;;
        json)
            command -v jq &>/dev/null || return 0
            jq . "$file" >/dev/null 2>&1 || echo "Invalid JSON: $file"
            ;;
        yaml)
            command -v yamllint &>/dev/null || return 0
            yamllint -d relaxed "$file" 2>&1
            ;;
        c|cpp)
            command -v cppcheck &>/dev/null || return 0
            cppcheck --quiet --error-exitcode=1 "$file" 2>&1
            ;;
        markdown)
            # Check frontmatter only
            if head -1 "$file" 2>/dev/null | grep -q '^---$'; then
                command -v yamllint &>/dev/null || return 0
                awk '/^---$/{if(++c==2)exit; next} c==1{print}' "$file" | yamllint -d relaxed - 2>&1
            fi
            ;;
    esac
}

output=$(run_diagnostic "$file_path" "$lang" 2>&1) || exit_code=$?
exit_code=${exit_code:-0}

if [[ $exit_code -ne 0 ]] && [[ -n "$output" ]]; then
    echo "" >&2
    echo "Diagnostic errors in $file_path:" >&2
    echo "$output" >&2
    echo "" >&2
fi

# Always exit 0 - don't block, just warn
exit 0
