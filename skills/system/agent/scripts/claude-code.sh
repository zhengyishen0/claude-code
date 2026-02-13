#!/bin/bash
#
# Claude Code wrapper with preconfigured settings
#
# Usage:
#   claude-code.sh "prompt"                    # New session with 'default' setting
#   claude-code.sh -r                          # Pick from recent sessions
#   claude-code.sh -r <partial>                # Resume session by partial ID
#   claude-code.sh -c                          # Continue last session
#   claude-code.sh -P <setting> "prompt"       # Use named setting
#   claude-code.sh --model X "prompt"          # Override model
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AGENT_DIR/config/agents.yaml"
SESSION_SCRIPT="$SCRIPT_DIR/session.sh"

# ─────────────────────────────────────────────────────────────
# Config parsing (settings.<name>.<key>)
# ─────────────────────────────────────────────────────────────

# Get a value from settings.<name>.<key>
get_config() {
    local key="$1"
    local fallback="${2:-}"
    local name="${3:-default}"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "$fallback"
        return
    fi

    local value=""
    local in_settings=false
    local in_name=false

    while IFS= read -r line; do
        # Find settings: block
        if [[ "$line" =~ ^settings: ]]; then
            in_settings=true
            continue
        fi

        # Exit settings on another top-level key
        if [[ "$in_settings" == true && "$line" =~ ^[a-z] ]]; then
            break
        fi

        if [[ "$in_settings" == true ]]; then
            # Find named setting (2-space indent)
            if [[ "$line" =~ ^[[:space:]]{2}${name}: ]]; then
                in_name=true
                continue
            fi

            # Exit named setting on another 2-space key
            if [[ "$in_name" == true && "$line" =~ ^[[:space:]]{2}[a-z] ]]; then
                break
            fi

            # Find key (4-space indent)
            if [[ "$in_name" == true && "$line" =~ ^[[:space:]]{4}${key}:[[:space:]]*(.*)$ ]]; then
                value="${BASH_REMATCH[1]}"
                value="${value%%#*}"  # Remove comments
                value="$(echo "$value" | xargs)"  # Trim
                break
            fi
        fi
    done < "$CONFIG_FILE"

    [[ -n "$value" ]] && echo "$value" || echo "$fallback"
}

# Get system prompts list and concatenate files
get_system_prompt() {
    local name="${1:-default}"
    local config_dir
    config_dir="$(dirname "$CONFIG_FILE")"
    local in_settings=false
    local in_name=false
    local in_list=false
    local prompt=""

    [[ ! -f "$CONFIG_FILE" ]] && return

    while IFS= read -r line; do
        # Find settings: block
        if [[ "$line" =~ ^settings: ]]; then
            in_settings=true
            continue
        fi

        if [[ "$in_settings" == true && "$line" =~ ^[a-z] ]]; then
            break
        fi

        if [[ "$in_settings" == true ]]; then
            # Find named setting
            if [[ "$line" =~ ^[[:space:]]{2}${name}: ]]; then
                in_name=true
                continue
            fi

            if [[ "$in_name" == true && "$line" =~ ^[[:space:]]{2}[a-z] ]]; then
                break
            fi

            if [[ "$in_name" == true ]]; then
                # Check for system_prompts list
                if [[ "$line" =~ ^[[:space:]]{4}system_prompts: ]]; then
                    in_list=true
                    continue
                fi

                # Exit list if new key at same indent
                if [[ "$in_list" == true && "$line" =~ ^[[:space:]]{4}[a-z_]+: ]]; then
                    break
                fi

                # Parse "      - path" entries (6-space indent)
                if [[ "$in_list" == true && "$line" =~ ^[[:space:]]{6}-[[:space:]]*(.+)$ ]]; then
                    local path="${BASH_REMATCH[1]}"
                    [[ "$path" =~ ^# ]] && continue
                    path="${path%%#*}"
                    path="$(echo "$path" | xargs)"

                    # Resolve relative paths
                    if [[ "$path" != /* ]]; then
                        path="$config_dir/$path"
                    fi

                    # Concatenate file content
                    if [[ -f "$path" ]]; then
                        [[ -n "$prompt" ]] && prompt+=$'\n\n'
                        prompt+="$(cat "$path")"
                    fi
                fi
            fi
        fi
    done < "$CONFIG_FILE"

    echo "$prompt"
}

# Get skills list using next list
get_skills_prompt() {
    local next_script="$AGENT_DIR/../next/run.sh"

    [[ ! -x "$next_script" ]] && return

    # Run next list and strip ANSI colors
    "$next_script" list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
}

# Check if setting exists
setting_exists() {
    local name="$1"
    grep -q "^[[:space:]]*${name}:" "$CONFIG_FILE" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────
# Session management
# ─────────────────────────────────────────────────────────────

show_recent_sessions() {
    if [[ ! -x "$SESSION_SCRIPT" ]]; then
        echo "Session script not found" >&2
        return 1
    fi

    echo "Recent sessions:" >&2
    echo "" >&2
    "$SESSION_SCRIPT" list 10
    echo "" >&2
    echo "Usage: agent -r <partial-id>" >&2
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

SETTING="default"
MODEL=""
PERMISSIONS=""
SYSTEM_PROMPT=""

CLAUDE_ARGS=()
PROMPT=""
RESUME_ID=""
CONTINUE=false
SHOW_SESSIONS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--resume)
            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                RESUME_ID="$2"
                shift 2
            else
                SHOW_SESSIONS=true
                shift
            fi
            ;;
        -c|--continue)
            CONTINUE=true
            shift
            ;;
        -P|--setting)
            SETTING="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --permissions)
            PERMISSIONS="$2"
            shift 2
            ;;
        -p)
            CLAUDE_ARGS+=("-p" "$2")
            shift 2
            ;;
        --*)
            CLAUDE_ARGS+=("$1")
            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                CLAUDE_ARGS+=("$2")
                shift
            fi
            shift
            ;;
        *)
            PROMPT="$1"
            shift
            ;;
    esac
done

# Show sessions if requested
if [[ "$SHOW_SESSIONS" == true ]]; then
    show_recent_sessions
    exit 0
fi

# Load from setting
if ! setting_exists "$SETTING"; then
    echo "Setting not found: $SETTING" >&2
    exit 1
fi

[[ -z "$MODEL" ]] && MODEL=$(get_config "model" "claude-opus-4-5" "$SETTING")
[[ -z "$PERMISSIONS" ]] && PERMISSIONS=$(get_config "permissions" "auto" "$SETTING")
WORKSPACE=$(get_config "workspace" "false" "$SETTING")
SYSTEM_PROMPT=$(get_system_prompt "$SETTING")
SKILLS_PROMPT=$(get_skills_prompt "$SETTING")

# Workspace: generate session ID and grant access
if [[ "$WORKSPACE" == "true" ]]; then
    CLAUDE_SESSION_ID=$(openssl rand -hex 4)
    WORKSPACE_PATH="$HOME/.workspace/[${CLAUDE_SESSION_ID}]"
    export CLAUDE_SESSION_ID
    CLAUDE_ARGS+=("--add-dir" "$HOME/.workspace")
fi

# Combine system prompt and skills
if [[ -n "$SKILLS_PROMPT" ]]; then
    if [[ -n "$SYSTEM_PROMPT" ]]; then
        SYSTEM_PROMPT+=$'\n\n# Skills\n\n'"$SKILLS_PROMPT"
    else
        SYSTEM_PROMPT="# Skills"$'\n\n'"$SKILLS_PROMPT"
    fi
fi

# Add model
CLAUDE_ARGS+=("--model" "$MODEL")

# Add permissions
case "$PERMISSIONS" in
    auto)
        CLAUDE_ARGS+=("--dangerously-skip-permissions")
        ;;
    default)
        CLAUDE_ARGS+=("--allow-dangerously-skip-permissions")
        ;;
esac

# Add system prompt if configured
if [[ -n "$SYSTEM_PROMPT" ]]; then
    CLAUDE_ARGS+=("--append-system-prompt" "$SYSTEM_PROMPT")
fi

# Handle resume/continue
if [[ -n "$RESUME_ID" ]]; then
    if [[ -x "$SESSION_SCRIPT" ]]; then
        FULL_ID=$("$SESSION_SCRIPT" find "$RESUME_ID") || {
            echo "Session not found: $RESUME_ID" >&2
            echo "" >&2
            show_recent_sessions
            exit 1
        }
        echo "Resuming: $FULL_ID" >&2
        CLAUDE_ARGS+=("--resume" "$FULL_ID")
    else
        CLAUDE_ARGS+=("--resume" "$RESUME_ID")
    fi
elif [[ "$CONTINUE" == true ]]; then
    CLAUDE_ARGS+=("--continue")
fi

# Add prompt if provided
if [[ -n "$PROMPT" ]]; then
    CLAUDE_ARGS+=("$PROMPT")
fi

# Execute
exec claude "${CLAUDE_ARGS[@]}"
