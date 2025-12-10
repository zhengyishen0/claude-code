#!/bin/bash
# context7 - Fetch up-to-date library documentation via Context7 API
# Usage: context7 <command> [args...]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_NAME="$(basename "$SCRIPT_DIR")"

# ============================================================================
# Configuration
# ============================================================================

API_BASE="https://context7.com/api"

# Check for API key
check_api_key() {
  if [ -z "$CONTEXT7_API_KEY" ]; then
    echo "Error: No API key set" >&2
    echo "" >&2
    echo "Get your API key at: https://context7.com/dashboard" >&2
    echo "" >&2
    echo "Then use one of these methods:" >&2
    echo "  1. Flag:    $TOOL_NAME --api-key 'your-key' search react" >&2
    echo "  2. Export:  export CONTEXT7_API_KEY='your-key'" >&2
    return 1
  fi
}

# ============================================================================
# Command: search
# ============================================================================
cmd_search() {
  local QUERY="$1"

  if [ -z "$QUERY" ]; then
    echo "Usage: $TOOL_NAME search <query>" >&2
    echo "" >&2
    echo "Example: $TOOL_NAME search react" >&2
    return 1
  fi

  check_api_key || return 1

  # URL encode query
  QUERY_ENCODED=$(printf %s "$QUERY" | jq -sRr @uri)

  # Make API request
  response=$(curl -s "${API_BASE}/v2/search?query=${QUERY_ENCODED}" \
    -H "Authorization: Bearer ${CONTEXT7_API_KEY}")

  # Check for errors
  if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
    echo "API Error:" >&2
    echo "$response" | jq -r '.error' >&2
    return 1
  fi

  # Format output
  echo "$response" | jq -r '
    .results[] |
    "ID: \(.id)\n" +
    "Title: \(.title)\n" +
    "Description: \(.description)\n" +
    "Stars: \(.stars)\n" +
    "Snippets: \(.totalSnippets)\n" +
    "Trust Score: \(.trustScore)\n" +
    "---"
  '
}

# ============================================================================
# Command: docs
# ============================================================================
cmd_docs() {
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
    echo "Usage: $TOOL_NAME docs <library-id> [options]" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  --topic <topic>      Filter by topic (e.g., 'routing', 'hooks')" >&2
    echo "  --version <version>  Get specific version docs" >&2
    echo "  --format txt|json    Output format (default: txt)" >&2
    echo "" >&2
    echo "Example: $TOOL_NAME docs vercel/next.js --topic routing --format txt" >&2
    return 1
  fi

  check_api_key || return 1

  # Remove leading slash if present
  LIBRARY_ID="${LIBRARY_ID#/}"

  # Build URL
  local url="${API_BASE}/v2/docs/code/${LIBRARY_ID}"

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
    # txt format - just output directly
    echo "$response"
  fi
}

# ============================================================================
# Command: help
# ============================================================================
cmd_help() {
  echo "$TOOL_NAME - Fetch up-to-date library documentation via Context7 API"
  echo ""
  echo "Usage: $TOOL_NAME <command> [args...]"
  echo ""
  echo "Commands:"
  echo "  search <query>           Search for libraries in Context7"
  echo "  docs <library-id> [opts] Get documentation for a library"
  echo "  help                     Show this help message"
  echo ""
  echo "Search Examples:"
  echo "  $TOOL_NAME search react"
  echo "  $TOOL_NAME search \"next.js\""
  echo ""
  echo "Docs Examples:"
  echo "  $TOOL_NAME docs vercel/next.js --topic routing"
  echo "  $TOOL_NAME docs reactjs/react.dev --topic hooks --format json"
  echo "  $TOOL_NAME docs expressjs/express --topic middleware"
  echo ""
  echo "Docs Options:"
  echo "  --topic <topic>      Filter by topic (e.g., 'routing', 'hooks', 'middleware')"
  echo "  --version <version>  Get specific version docs"
  echo "  --format txt|json    Output format (default: txt for readable, json for parsing)"
  echo ""
  echo "Global Options:"
  echo "  --api-key <key>      Set API key for this command"
  echo ""
  echo "Setup (get API key at https://context7.com/dashboard):"
  echo "  1. Flag:    $TOOL_NAME --api-key 'your-key' search react"
  echo "  2. Export:  export CONTEXT7_API_KEY='your-key'"
  echo ""
  echo "For detailed documentation, see: $SCRIPT_DIR/README.md"
}

# ============================================================================
# Main execution
# ============================================================================

# Parse global flags
while [ $# -gt 0 ]; do
  case "$1" in
    --api-key)
      export CONTEXT7_API_KEY="$2"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

case "$1" in
  search)
    shift
    cmd_search "$@"
    ;;

  docs)
    shift
    cmd_docs "$@"
    ;;

  help|--help|-h)
    cmd_help
    ;;

  "")
    cmd_help
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run '$TOOL_NAME help' for usage" >&2
    exit 1
    ;;
esac
