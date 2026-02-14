#!/bin/bash
#
# Framework dispatcher
# Routes to framework-specific scripts based on provider.yaml config
#
# Usage:
#   dispatch.sh <model-alias> [args...]
#   dispatch.sh --framework <name> [args...]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AGENT_DIR/config/provider.yaml"

: "${ZENIX_WORKSPACE:=$HOME/.workspace}"

# ─────────────────────────────────────────────────────────────
# Workspace prefix derivation
#   - multi-word (a-b): initials → claude-code → cc
#   - single word: first+last → codex → cx
# ─────────────────────────────────────────────────────────────
get_workspace_prefix() {
    local name="$1"
    if [[ "$name" == *-* ]]; then
        # Multi-word: first letter of each
        echo "$name" | sed 's/\([a-z]\)[a-z]*-*/\1/g'
    else
        # Single word: first + last
        echo "${name:0:1}${name: -1}"
    fi
}

# ─────────────────────────────────────────────────────────────
# Config parsing
# ─────────────────────────────────────────────────────────────

# Get value from models.<alias>.<key>
get_model_config() {
    local alias="$1"
    local key="$2"
    local fallback="${3:-}"

    [[ ! -f "$CONFIG_FILE" ]] && echo "$fallback" && return

    local in_models=false
    local in_alias=false
    local value=""

    while IFS= read -r line; do
        # Find models: block
        if [[ "$line" =~ ^models: ]]; then
            in_models=true
            continue
        fi

        # Exit models on another top-level key
        if [[ "$in_models" == true && "$line" =~ ^[a-z] ]]; then
            break
        fi

        if [[ "$in_models" == true ]]; then
            # Find alias (2-space indent)
            if [[ "$line" =~ ^[[:space:]]{2}${alias}: ]]; then
                in_alias=true
                continue
            fi

            # Exit alias on another 2-space key
            if [[ "$in_alias" == true && "$line" =~ ^[[:space:]]{2}[a-z] ]]; then
                break
            fi

            # Find key (4-space indent)
            if [[ "$in_alias" == true && "$line" =~ ^[[:space:]]{4}${key}:[[:space:]]*(.*)$ ]]; then
                value="${BASH_REMATCH[1]}"
                value="${value%%#*}"
                value="$(echo "$value" | xargs)"
                break
            fi
        fi
    done < "$CONFIG_FILE"

    [[ -n "$value" ]] && echo "$value" || echo "$fallback"
}

# Get value from frameworks.<name>.<key>
get_framework_config() {
    local name="$1"
    local key="$2"
    local fallback="${3:-}"

    [[ ! -f "$CONFIG_FILE" ]] && echo "$fallback" && return

    local in_frameworks=false
    local in_name=false
    local value=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^frameworks: ]]; then
            in_frameworks=true
            continue
        fi

        if [[ "$in_frameworks" == true && "$line" =~ ^[a-z] ]]; then
            break
        fi

        if [[ "$in_frameworks" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}${name}: ]]; then
                in_name=true
                continue
            fi

            if [[ "$in_name" == true && "$line" =~ ^[[:space:]]{2}[a-z] ]]; then
                break
            fi

            if [[ "$in_name" == true && "$line" =~ ^[[:space:]]{4}${key}:[[:space:]]*(.*)$ ]]; then
                value="${BASH_REMATCH[1]}"
                value="${value%%#*}"
                value="$(echo "$value" | xargs)"
                break
            fi
        fi
    done < "$CONFIG_FILE"

    [[ -n "$value" ]] && echo "$value" || echo "$fallback"
}

# Get nested value from frameworks.<name>.<section>.<key>
get_framework_nested() {
    local name="$1"
    local section="$2"
    local key="$3"
    local fallback="${4:-}"

    [[ ! -f "$CONFIG_FILE" ]] && echo "$fallback" && return

    local in_frameworks=false
    local in_name=false
    local in_section=false
    local value=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^frameworks: ]]; then
            in_frameworks=true
            continue
        fi

        if [[ "$in_frameworks" == true && "$line" =~ ^[a-z] ]]; then
            break
        fi

        if [[ "$in_frameworks" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}${name}: ]]; then
                in_name=true
                continue
            fi

            if [[ "$in_name" == true && "$line" =~ ^[[:space:]]{2}[a-z] ]]; then
                break
            fi

            if [[ "$in_name" == true ]]; then
                if [[ "$line" =~ ^[[:space:]]{4}${section}: ]]; then
                    in_section=true
                    continue
                fi

                if [[ "$in_section" == true && "$line" =~ ^[[:space:]]{4}[a-z] ]]; then
                    break
                fi

                if [[ "$in_section" == true && "$line" =~ ^[[:space:]]{6}${key}:[[:space:]]*(.*)$ ]]; then
                    value="${BASH_REMATCH[1]}"
                    value="${value%%#*}"
                    value="$(echo "$value" | xargs)"
                    break
                fi
            fi
        fi
    done < "$CONFIG_FILE"

    [[ -n "$value" ]] && echo "$value" || echo "$fallback"
}

# Get default value
get_default() {
    local key="$1"
    local fallback="${2:-}"

    [[ ! -f "$CONFIG_FILE" ]] && echo "$fallback" && return

    local in_defaults=false
    local value=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^defaults: ]]; then
            in_defaults=true
            continue
        fi

        if [[ "$in_defaults" == true && "$line" =~ ^[a-z] ]]; then
            break
        fi

        if [[ "$in_defaults" == true && "$line" =~ ^[[:space:]]{2}${key}:[[:space:]]*(.*)$ ]]; then
            value="${BASH_REMATCH[1]}"
            value="${value%%#*}"
            value="$(echo "$value" | xargs)"
            break
        fi
    done < "$CONFIG_FILE"

    [[ -n "$value" ]] && echo "$value" || echo "$fallback"
}

# ─────────────────────────────────────────────────────────────
# Main dispatch logic
# ─────────────────────────────────────────────────────────────

MODEL_ALIAS=""
FRAMEWORK=""
PERMISSIONS=""
SYSTEM_PROMPT=""
SKILLS=""
PASSTHROUGH_ARGS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --framework|-f)
            FRAMEWORK="$2"
            shift 2
            ;;
        --model|-m)
            MODEL_ALIAS="$2"
            shift 2
            ;;
        --permissions)
            PERMISSIONS="$2"
            shift 2
            ;;
        --system-prompt)
            SYSTEM_PROMPT="$2"
            shift 2
            ;;
        --skills)
            SKILLS="$2"
            shift 2
            ;;
        *)
            PASSTHROUGH_ARGS+=("$1")
            shift
            ;;
    esac
done

# Resolve model alias to framework
if [[ -z "$MODEL_ALIAS" ]]; then
    MODEL_ALIAS=$(get_default "model" "opus")
fi

if [[ -z "$FRAMEWORK" ]]; then
    FRAMEWORK=$(get_model_config "$MODEL_ALIAS" "framework" "claude-code")
fi

# Validate framework exists
COMMAND=$(get_framework_config "$FRAMEWORK" "command" "")
if [[ -z "$COMMAND" ]]; then
    echo "Unknown framework: $FRAMEWORK" >&2
    exit 1
fi

# Resolve model ID from alias
MODEL_ID=$(get_model_config "$MODEL_ALIAS" "model" "$MODEL_ALIAS")

# Resolve permissions (arg > default)
if [[ -z "$PERMISSIONS" ]]; then
    PERMISSIONS=$(get_default "permissions" "auto")
fi

# Resolve workspace
WORKSPACE_ENABLED=$(get_default "workspace" "true")

# Derive workspace prefix (or use explicit override)
WORKSPACE_PREFIX=$(get_framework_config "$FRAMEWORK" "workspace_prefix" "")
if [[ -z "$WORKSPACE_PREFIX" ]]; then
    WORKSPACE_PREFIX=$(get_workspace_prefix "$FRAMEWORK")
fi

# Generate session ID and workspace path
SESSION_ID=$(openssl rand -hex 4)
WORKSPACE_NAME="${WORKSPACE_PREFIX}-${SESSION_ID}"
WORKSPACE_PATH="$ZENIX_WORKSPACE/${WORKSPACE_NAME}"

# Detect repo root from cwd
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# ─────────────────────────────────────────────────────────────
# Create workspace (if enabled)
# ─────────────────────────────────────────────────────────────

if [[ "$WORKSPACE_ENABLED" == "true" ]]; then
    # Create workspace directory
    mkdir -p "$WORKSPACE_PATH"

    # Create jj workspace linked to repo
    (cd "$REPO_ROOT" && jj workspace add --name "$WORKSPACE_NAME" "$WORKSPACE_PATH" 2>/dev/null) || {
        echo "Warning: Failed to create jj workspace" >&2
    }

    # Write repo root for work skill
    echo "$REPO_ROOT" > "$WORKSPACE_PATH/.repo_root"
fi

# ─────────────────────────────────────────────────────────────
# Export unified interface for framework parsers
# ─────────────────────────────────────────────────────────────

# Identity
export ZENIX_SESSION_ID="$SESSION_ID"
export ZENIX_FRAMEWORK="$FRAMEWORK"

# Workspace
export ZENIX_WORKSPACE_PATH="$WORKSPACE_PATH"
export ZENIX_WORKSPACE_ENABLED="$WORKSPACE_ENABLED"
export ZENIX_REPO_ROOT="$REPO_ROOT"

# Model
export ZENIX_MODEL_ALIAS="$MODEL_ALIAS"
export ZENIX_MODEL_ID="$MODEL_ID"

# Behavior
export ZENIX_PERMISSIONS="$PERMISSIONS"

# Content
export ZENIX_SYSTEM_PROMPT="$SYSTEM_PROMPT"
export ZENIX_SKILLS="$SKILLS"

# ─────────────────────────────────────────────────────────────
# Execute framework parser
# ─────────────────────────────────────────────────────────────

FRAMEWORK_SCRIPT="$SCRIPT_DIR/${FRAMEWORK}.sh"
if [[ -x "$FRAMEWORK_SCRIPT" ]]; then
    exec "$FRAMEWORK_SCRIPT" "${PASSTHROUGH_ARGS[@]}"
else
    echo "Framework script not found: $FRAMEWORK_SCRIPT" >&2
    exit 1
fi
