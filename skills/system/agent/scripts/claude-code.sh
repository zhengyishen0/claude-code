#!/bin/bash
#
# Claude Code wrapper with preconfigured settings
#
# Usage:
#   claude-code.sh "prompt"                    # New session with defaults
#   claude-code.sh -r                          # Pick from recent sessions
#   claude-code.sh -r <partial>                # Resume session by partial ID
#   claude-code.sh -c                          # Continue last session
#   claude-code.sh -P <profile> "prompt"       # Use named profile
#   claude-code.sh --model X "prompt"          # Override model
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AGENT_DIR/config/agents.yaml"
SESSION_SCRIPT="$SCRIPT_DIR/session.sh"

# ─────────────────────────────────────────────────────────────
# Config parsing
# ─────────────────────────────────────────────────────────────

# Get a simple key: value from config (handles defaults.key and profiles.name.key)
get_config() {
    local key="$1"
    local default="${2:-}"
    local section="${3:-defaults}"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "$default"
        return
    fi

    local value=""
    local in_section=false

    while IFS= read -r line; do
        # Check for section start
        if [[ "$section" == "defaults" && "$line" =~ ^defaults: ]]; then
            in_section=true
            continue
        elif [[ "$section" != "defaults" && "$line" =~ ^[[:space:]]*${section}: ]]; then
            in_section=true
            continue
        fi

        if [[ "$in_section" == true ]]; then
            # Exit section on non-indented line
            if [[ "$line" =~ ^[^[:space:]] && ! "$line" =~ ^$ ]]; then
                break
            fi

            # Look for key
            if [[ "$line" =~ ^[[:space:]]+${key}:[[:space:]]*(.*)$ ]]; then
                value="${BASH_REMATCH[1]}"
                value="${value%%#*}"  # Remove comments
                value="$(echo "$value" | xargs)"  # Trim
                break
            fi
        fi
    done < "$CONFIG_FILE"

    [[ -n "$value" ]] && echo "$value" || echo "$default"
}

# Get system prompts list and concatenate files
get_system_prompt() {
    local section="${1:-defaults}"
    local config_dir
    config_dir="$(dirname "$CONFIG_FILE")"
    local in_section=false
    local in_list=false
    local prompt=""

    while IFS= read -r line; do
        # Find section
        if [[ "$section" == "defaults" && "$line" =~ ^defaults: ]]; then
            in_section=true
            continue
        elif [[ "$section" != "defaults" && "$line" =~ ^[[:space:]]*${section}: ]]; then
            in_section=true
            continue
        fi

        if [[ "$in_section" == true ]]; then
            # Exit section on non-indented line
            if [[ "$line" =~ ^[^[:space:]] && ! "$line" =~ ^$ ]]; then
                break
            fi

            # Check for system_prompts list
            if [[ "$line" =~ ^[[:space:]]+system_prompts: ]]; then
                in_list=true
                continue
            fi

            # If in list, look for "- path" entries
            if [[ "$in_list" == true ]]; then
                # Exit list if new key at same indent
                if [[ "$line" =~ ^[[:space:]]+[a-z_]+: ]]; then
                    in_list=false
                    continue
                fi

                # Parse "  - path" entries
                if [[ "$line" =~ ^[[:space:]]+-[[:space:]]*(.+)$ ]]; then
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

# Get skills list and use skill content command
get_skills_prompt() {
    local section="${1:-defaults}"
    local skill_script="$AGENT_DIR/../skill/run.sh"
    local in_section=false
    local in_list=false
    local prompt=""

    [[ ! -x "$skill_script" ]] && return

    # Helper to fetch and append skill content
    fetch_skill() {
        local target="$1"
        local content
        content=$("$skill_script" content "$target" 2>/dev/null) || return
        if [[ -n "$content" ]]; then
            [[ -n "$prompt" ]] && prompt+=$'\n\n'
            prompt+="$content"
        fi
    }

    while IFS= read -r line; do
        # Find section
        if [[ "$section" == "defaults" && "$line" =~ ^defaults: ]]; then
            in_section=true
            continue
        elif [[ "$section" != "defaults" && "$line" =~ ^[[:space:]]*${section}: ]]; then
            in_section=true
            continue
        fi

        if [[ "$in_section" == true ]]; then
            # Exit section on non-indented line
            if [[ "$line" =~ ^[^[:space:]] && ! "$line" =~ ^$ ]]; then
                break
            fi

            # Check for skills - inline format: skills: [a, b, c]
            if [[ "$line" =~ ^[[:space:]]+skills:[[:space:]]*\[(.+)\] ]]; then
                local inline="${BASH_REMATCH[1]}"
                # Split by comma and process each
                IFS=',' read -ra targets <<< "$inline"
                for target in "${targets[@]}"; do
                    target="$(echo "$target" | xargs)"  # trim
                    [[ -n "$target" ]] && fetch_skill "$target"
                done
                continue
            fi

            # Check for skills list format
            if [[ "$line" =~ ^[[:space:]]+skills: ]]; then
                in_list=true
                continue
            fi

            # If in list, look for "- target" entries
            if [[ "$in_list" == true ]]; then
                # Exit list if new key at same indent
                if [[ "$line" =~ ^[[:space:]]+[a-z_]+: ]]; then
                    in_list=false
                    continue
                fi

                # Parse "  - target" entries
                if [[ "$line" =~ ^[[:space:]]+-[[:space:]]*(.+)$ ]]; then
                    local target="${BASH_REMATCH[1]}"
                    [[ "$target" =~ ^# ]] && continue
                    target="${target%%#*}"
                    target="$(echo "$target" | xargs)"
                    fetch_skill "$target"
                fi
            fi
        fi
    done < "$CONFIG_FILE"

    echo "$prompt"
}

# Check if profile exists
profile_exists() {
    local profile="$1"
    grep -q "^[[:space:]]*${profile}:" "$CONFIG_FILE" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────
# Session management
# ─────────────────────────────────────────────────────────────

# Show recent sessions for selection
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

# Defaults
PROFILE=""
MODEL=""
PERMISSIONS=""
SYSTEM_PROMPT=""

# Build claude args
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
        -P|--profile)
            PROFILE="$2"
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

# Load from profile or defaults
SKILLS_PROMPT=""
if [[ -n "$PROFILE" ]]; then
    if ! profile_exists "$PROFILE"; then
        echo "Profile not found: $PROFILE" >&2
        exit 1
    fi
    [[ -z "$MODEL" ]] && MODEL=$(get_config "model" "" "$PROFILE")
    [[ -z "$PERMISSIONS" ]] && PERMISSIONS=$(get_config "permissions" "" "$PROFILE")
    SYSTEM_PROMPT=$(get_system_prompt "$PROFILE")
    SKILLS_PROMPT=$(get_skills_prompt "$PROFILE")
fi

# Fall back to defaults
[[ -z "$MODEL" ]] && MODEL=$(get_config "model" "claude-sonnet-4-5-20250929" "defaults")
[[ -z "$PERMISSIONS" ]] && PERMISSIONS=$(get_config "permissions" "default" "defaults")
[[ -z "$SYSTEM_PROMPT" ]] && SYSTEM_PROMPT=$(get_system_prompt "defaults")
[[ -z "$SKILLS_PROMPT" ]] && SKILLS_PROMPT=$(get_skills_prompt "defaults")

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
