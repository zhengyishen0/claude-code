#!/bin/bash
# documentation - Get external documentation for libraries, commands, and APIs
# Usage: documentation <command> [args...]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_NAME="$(basename "$SCRIPT_DIR")"

# ============================================================================
# Configuration
# ============================================================================

CONTEXT7_API_BASE="https://context7.com/api"
CHEATSH_BASE="https://cht.sh"
APIGURU_BASE="https://api.apis.guru/v2"

# ============================================================================
# Helper: Check API key for context7
# ============================================================================
check_context7_key() {
  if [ -z "$CONTEXT7_API_KEY" ]; then
    echo "Error: No Context7 API key set" >&2
    echo "" >&2
    echo "Set your API key (get one at https://context7.com/dashboard):" >&2
    echo "  $TOOL_NAME config context7 'your-key'" >&2
    return 1
  fi
}

# ============================================================================
# Command: library
# ============================================================================
cmd_library() {
  local LIBRARY_ID=""
  local TOPIC=""
  local VERSION=""
  local FORMAT="txt"

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --topic)
        TOPIC="$2"
        shift 2
        ;;
      --version)
        VERSION="$2"
        shift 2
        ;;
      --format)
        FORMAT="$2"
        shift 2
        ;;
      -*)
        echo "Unknown option: $1" >&2
        echo "Run '$TOOL_NAME library --help' for usage" >&2
        return 1
        ;;
      *)
        if [ -z "$LIBRARY_ID" ]; then
          LIBRARY_ID="$1"
        else
          echo "Unexpected argument: $1" >&2
          return 1
        fi
        shift
        ;;
    esac
  done

  if [ -z "$LIBRARY_ID" ]; then
    echo "Usage: $TOOL_NAME library <library-id> [options]" >&2
    echo "" >&2
    echo "Get documentation for a library via Context7 API" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  --topic <topic>      Filter by topic (e.g., 'routing', 'hooks')" >&2
    echo "  --version <version>  Get specific version docs" >&2
    echo "  --format txt|json    Output format (default: txt)" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $TOOL_NAME library vercel/next.js --topic routing" >&2
    echo "  $TOOL_NAME library reactjs/react.dev --topic hooks" >&2
    echo "  $TOOL_NAME library expressjs/express --topic middleware --format json" >&2
    echo "" >&2
    echo "First time? Search for libraries:" >&2
    echo "  $TOOL_NAME library --search react" >&2
    return 1
  fi

  check_context7_key || return 1

  # Remove leading slash if present
  LIBRARY_ID="${LIBRARY_ID#/}"

  # Build URL
  local url="${CONTEXT7_API_BASE}/v2/docs/code/${LIBRARY_ID}"

  # Add version if specified
  if [ -n "$VERSION" ]; then
    url="${url}/${VERSION}"
  fi

  # Build query string
  local query_params="type=${FORMAT}"
  if [ -n "$TOPIC" ]; then
    TOPIC_ENCODED=$(printf %s "$TOPIC" | jq -sRr @uri)
    query_params="${query_params}&topic=${TOPIC_ENCODED}"
  fi

  url="${url}?${query_params}"

  # Make API request
  response=$(curl -s "$url" -H "Authorization: Bearer ${CONTEXT7_API_KEY}")

  # Check for errors
  if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
    echo "API Error:" >&2
    echo "$response" | jq -r '.error' >&2
    return 1
  fi

  # Output based on format
  if [ "$FORMAT" = "json" ]; then
    echo "$response" | jq '.'
  else
    # txt format - output directly
    echo "$response"
  fi
}

# ============================================================================
# Command: command
# ============================================================================
cmd_command() {
  local query="$1"

  if [ -z "$query" ]; then
    echo "Usage: $TOOL_NAME command <command-name>" >&2
    echo "" >&2
    echo "Get CLI command examples via cheat.sh" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $TOOL_NAME command tar" >&2
    echo "  $TOOL_NAME command git" >&2
    echo "  $TOOL_NAME command docker" >&2
    echo "  $TOOL_NAME command jq" >&2
    echo "" >&2
    echo "For programming languages, use spaces with quotes:" >&2
    echo '  $TOOL_NAME command "python/reverse list"' >&2
    echo '  $TOOL_NAME command "javascript/sort array"' >&2
    echo "" >&2
    echo "Search examples:" >&2
    echo '  $TOOL_NAME command "~docker~compose"' >&2
    return 1
  fi

  # Make request to cheat.sh
  local url="${CHEATSH_BASE}/${query}?T"
  response=$(curl -s "$url")

  if [ -z "$response" ]; then
    echo "Error: No results found for '$query'" >&2
    return 1
  fi

  echo "$response"
}

# ============================================================================
# Command: api
# ============================================================================
cmd_api() {
  local api_name="$1"
  local action="${2:-spec}"

  if [ -z "$api_name" ]; then
    echo "Usage: $TOOL_NAME api <api-name|--list> [spec|info]" >&2
    echo "" >&2
    echo "Get REST API specifications via APIs.guru" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $TOOL_NAME api --list              # List all available APIs" >&2
    echo "  $TOOL_NAME api stripe.com          # Get Stripe API spec" >&2
    echo "  $TOOL_NAME api github.com info     # Get GitHub API info only" >&2
    echo "  $TOOL_NAME api twitter.com spec    # Get Twitter API spec" >&2
    return 1
  fi

  # Special case: list all APIs
  if [ "$api_name" = "--list" ]; then
    response=$(curl -s "${APIGURU_BASE}/list.json")
    echo "$response" | jq -r 'to_entries | .[] | "\(.key)"' | sort
    return 0
  fi

  # First, get the list to find the API and its preferred version
  local list_response=$(curl -s "${APIGURU_BASE}/list.json")

  # Extract the API entry
  local api_entry=$(echo "$list_response" | jq -r --arg api "$api_name" '.[$api]')

  if [ "$api_entry" = "null" ] || [ -z "$api_entry" ]; then
    echo "Error: API '$api_name' not found" >&2
    echo "" >&2
    echo "List available APIs:" >&2
    echo "  $TOOL_NAME api --list" >&2
    return 1
  fi

  # Get the preferred version
  local version=$(echo "$api_entry" | jq -r '.preferred')

  if [ "$action" = "info" ]; then
    # Get just the info from the list response
    echo "$api_entry" | jq --arg ver "$version" '.versions[$ver].info'
  else
    # Get the full OpenAPI spec
    response=$(curl -s "${APIGURU_BASE}/specs/${api_name}/${version}/swagger.json")

    if [ -z "$response" ]; then
      echo "Error: Failed to fetch spec for '$api_name'" >&2
      return 1
    fi

    echo "$response" | jq '.'
  fi
}

# ============================================================================
# Command: config
# ============================================================================
cmd_config() {
  local service="$1"
  local key="$2"

  if [ -z "$service" ]; then
    echo "Usage: $TOOL_NAME config <service> [key]" >&2
    echo "" >&2
    echo "Configure API keys for documentation services" >&2
    echo "" >&2
    echo "Services:" >&2
    echo "  context7    Context7 API (required for 'library' command)" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $TOOL_NAME config context7 'ctx7sk-your-key'  # Set key" >&2
    echo "  $TOOL_NAME config context7                     # Check status" >&2
    return 1
  fi

  case "$service" in
    context7)
      if [ -z "$key" ]; then
        # Show current status
        if [ -n "$CONTEXT7_API_KEY" ]; then
          echo "Context7 API key is set"
        else
          echo "No Context7 API key set" >&2
          echo "" >&2
          echo "Get your free API key at: https://context7.com/dashboard" >&2
          echo "" >&2
          echo "Then set it:" >&2
          echo "  $TOOL_NAME config context7 'your-key'" >&2
          return 1
        fi
        return 0
      fi

      # Detect shell profile
      local shell_profile=""
      if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
        shell_profile="$HOME/.zshrc"
      elif [ -n "$BASH_VERSION" ] || [ -f "$HOME/.bashrc" ]; then
        shell_profile="$HOME/.bashrc"
      else
        shell_profile="$HOME/.zshrc"  # default to zsh
      fi

      local export_line="export CONTEXT7_API_KEY='$key'"

      # Check if already exists
      if grep -q "^export CONTEXT7_API_KEY=" "$shell_profile" 2>/dev/null; then
        # Update existing line
        if [[ "$OSTYPE" == "darwin"* ]]; then
          sed -i '' "s|^export CONTEXT7_API_KEY=.*|$export_line|" "$shell_profile"
        else
          sed -i "s|^export CONTEXT7_API_KEY=.*|$export_line|" "$shell_profile"
        fi
        echo "✓ Updated CONTEXT7_API_KEY in $shell_profile"
      else
        # Add new line
        echo "" >> "$shell_profile"
        echo "# Context7 API key for documentation tool" >> "$shell_profile"
        echo "$export_line" >> "$shell_profile"
        echo "✓ Added CONTEXT7_API_KEY to $shell_profile"
      fi

      echo ""
      echo "To use the API key, restart your terminal or run:"
      echo "  source $shell_profile"
      ;;

    *)
      echo "Unknown service: $service" >&2
      echo "Run '$TOOL_NAME config' for usage" >&2
      return 1
      ;;
  esac
}

# ============================================================================
# Command: help
# ============================================================================
cmd_help() {
  echo "$TOOL_NAME - Get external documentation for libraries, commands, and APIs"
  echo ""
  echo "Usage: $TOOL_NAME <command> [args...]"
  echo ""
  echo "Commands:"
  echo "  library <lib-id> [opts]   Get library documentation (via Context7)"
  echo "  command <cmd>             Get CLI command examples (via cheat.sh)"
  echo "  api <name> [spec|info]    Get REST API specifications (via APIs.guru)"
  echo "  config <service> [key]    Configure API keys"
  echo "  (no args)                 Show this help message"
  echo ""
  echo "Library Examples:"
  echo "  $TOOL_NAME library vercel/next.js --topic routing"
  echo "  $TOOL_NAME library reactjs/react.dev --topic hooks"
  echo ""
  echo "Command Examples:"
  echo "  $TOOL_NAME command tar"
  echo "  $TOOL_NAME command git"
  echo '  $TOOL_NAME command "python/reverse list"'
  echo ""
  echo "API Examples:"
  echo "  $TOOL_NAME api --list"
  echo "  $TOOL_NAME api stripe.com"
  echo "  $TOOL_NAME api github.com info"
  echo ""
  echo "Configuration:"
  echo "  $TOOL_NAME config context7 'your-key'"
  echo ""
  echo "For detailed help on a command, run it without arguments."
}

# ============================================================================
# Main execution
# ============================================================================

case "$1" in
  library)
    shift
    cmd_library "$@"
    ;;

  command)
    shift
    cmd_command "$@"
    ;;

  api)
    shift
    cmd_api "$@"
    ;;

  config)
    shift
    cmd_config "$@"
    ;;

  "")
    cmd_help
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run '$TOOL_NAME' for usage" >&2
    exit 1
    ;;
esac
