#!/bin/bash
# Universal tool entry point
# Usage: tools/run.sh <tool> [command] [args...]

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"

# Show help
show_help() {
  echo "tools/run.sh - Universal tool entry point"
  echo ""
  echo "Usage:"
  echo "  tools/run.sh <tool> [command] [args...]"
  echo ""
  echo "Commands:"
  echo "  init                        Check and install all prerequisites"
  echo "  sync                        Update CLAUDE.md/AGENT.md tools section"
  echo "  help, --help                Show this help message"
  echo ""
  echo "New Tool Structure:"
  echo "  tools/<name>/"
  echo "  ├── run.sh              Required - entry point (executable)"
  echo "  ├── commands/           Recommended"
  echo "  │   ├── help.sh         Recommended - called with no args"
  echo "  │   └── prereq.sh       Recommended - checks dependencies"
  echo "  └── ..."
  echo ""
  echo "Tool run.sh should:"
  echo "  - Show help + prereq check when called with no args"
  echo "  - Show help only when called with 'help'"
  echo "  - Derive tool name from folder: TOOL_NAME=\"\$(basename \"\$SCRIPT_DIR\")\""
  echo ""
  echo "Help output format (for sync):"
  echo "  Line 1: \"<name> - <description>\""
  echo "  Optional: \"Commands:\" section"
  echo "  Optional: \"Key Principles:\" section"
}

# List tools with status
list_tools() {
  echo "Tools:"
  for dir in "$TOOLS_DIR"/*/; do
    name=$(basename "$dir")

    # Skip if not a directory
    [[ ! -d "$dir" ]] && continue

    # Check requirements
    has_run=false
    has_help=false
    has_prereq=false
    help_format_ok=false
    cmds_have_help=true
    missing_help_cmds=""

    [[ -x "$dir/run.sh" ]] && has_run=true
    [[ -x "$dir/commands/help.sh" ]] && has_help=true
    [[ -x "$dir/commands/prereq.sh" ]] && has_prereq=true

    # Check help format if run.sh exists
    if $has_run; then
      help_line1=$("$dir/run.sh" help 2>/dev/null | head -1)
      # Check format: "<name> - <description>"
      if [[ "$help_line1" =~ ^[a-zA-Z0-9_-]+\ -\  ]]; then
        help_format_ok=true
      fi

      # Check each command in commands/ has --help
      if [[ -d "$dir/commands" ]]; then
        for cmd in "$dir/commands"/*.sh; do
          [[ ! -x "$cmd" ]] && continue
          cmd_name=$(basename "$cmd" .sh)
          [[ "$cmd_name" == "help" || "$cmd_name" == "prereq" ]] && continue
          cmd_help_output=$("$cmd" --help 2>/dev/null)
          cmd_noarg_output=$("$cmd" 2>/dev/null)
          # Check --help produces output AND differs from no-arg output
          if [[ -z "$cmd_help_output" ]] || [[ "$cmd_help_output" == "$cmd_noarg_output" ]]; then
            cmds_have_help=false
            missing_help_cmds+=" $cmd_name"
          fi
        done
      fi
    fi

    # Build status
    issues=""
    if ! $has_run; then
      echo "  ✗ $name (missing run.sh)"
      continue
    fi
    if ! $has_help; then issues+="help.sh, "; fi
    if ! $has_prereq; then issues+="prereq.sh, "; fi
    if ! $help_format_ok; then issues+="help format, "; fi
    if ! $cmds_have_help; then issues+="--help:$missing_help_cmds, "; fi

    if [[ -z "$issues" ]]; then
      echo "  ✓ $name"
    else
      issues=${issues%, }  # Remove trailing ", "
      echo "  ⚠ $name (missing $issues)"
    fi
  done
}

# Sync tools info to markdown file
# Reads from each tool's README.md instead of help output
sync_md() {
  local start_marker="<!-- TOOLS:AUTO-GENERATED -->"
  local end_marker="<!-- TOOLS:END -->"
  local md_file=""

  # Find markdown file with markers
  for candidate in "$TOOLS_DIR/../CLAUDE.md" "$TOOLS_DIR/../AGENT.md"; do
    if [[ -f "$candidate" ]] && grep -q "$start_marker" "$candidate"; then
      md_file="$candidate"
      break
    fi
  done

  if [[ -z "$md_file" ]]; then
    echo "No CLAUDE.md or AGENT.md with markers found"
    exit 0
  fi

  # Generate tools section
  local content=""
  content+="$start_marker\n\n"
  content+="Universal entry: \`tools/run.sh <tool> [command] [args...]\`\n\n"

  for dir in "$TOOLS_DIR"/*/; do
    [[ ! -d "$dir" ]] && continue

    local name=$(basename "$dir")
    local readme="$dir/README.md"

    # Skip if README doesn't exist
    if [[ ! -f "$readme" ]]; then
      echo "⚠ $name: No README.md found, skipping"
      continue
    fi

    # Extract description (first non-empty line after first # heading)
    local description=$(awk '/^# /{flag=1; next} flag && NF>0 {print; exit}' "$readme")

    # Extract commands from ## Commands section
    # Look for lines starting with ### (command names)
    local commands=$(awk '
      /^## Commands/ {flag=1; next}
      /^## / && flag {flag=0}
      flag && /^### / {
        gsub(/^### /, "")
        gsub(/:.*/, "")
        commands = commands (commands ? ", " : "") $0
      }
      END {print commands}
    ' "$readme")

    # Extract key principles from ## Key Principles section
    local principles=$(awk '
      /^## Key Principles/ {flag=1; next}
      /^## / && flag {flag=0}
      flag && /^[0-9]+\./ {print}
    ' "$readme")

    # Validation
    if [[ -z "$description" ]]; then
      echo "⚠ $name: No description found (add line after # heading)"
      description="No description"
    fi

    content+="### $name\n"
    content+="$description\n\n"
    content+="Run \`tools/$name/run.sh\` for full help.\n\n"

    if [[ -n "$commands" ]]; then
      content+="**Commands:** $commands\n\n"
    fi

    if [[ -n "$principles" ]]; then
      content+="**Key Principles:**\n"
      while IFS= read -r line; do
        content+="$line\n"
      done <<< "$principles"
      content+="\n"
    fi

    echo "✓ Synced: $name"
  done

  content+="$end_marker"

  # Replace content between markers
  awk -v start="$start_marker" -v end="$end_marker" -v content="$content" '
    $0 ~ start { print content; skip=1; next }
    $0 ~ end { skip=0; next }
    !skip { print }
  ' "$md_file" > "$md_file.tmp" && mv "$md_file.tmp" "$md_file"

  echo ""
  echo "✓ Updated $(basename "$md_file")"
}

# Initialize project - check and install prerequisites
init_project() {
  echo "Claude Code - Prerequisites Check"
  echo "=================================="
  echo ""

  # Temporary file for storing prerequisites data
  local tmpfile="/tmp/claude-code-prereqs-$$"
  : > "$tmpfile"

  # Collect all prerequisites from tool READMEs
  for dir in "$TOOLS_DIR"/*/; do
    [ ! -d "$dir" ] && continue
    local readme="$dir/README.md"
    [ ! -f "$readme" ] && continue

    # Extract prerequisites and save to temp file
    # Format: tool|type|cmd
    awk '/^## Prerequisites/{flag=1; next} flag && /^## /{flag=0} flag && /^- /{print}' "$readme" | while IFS= read -r line; do
      # Parse: - tool (required|optional): install command
      echo "$line" | sed -E 's/^- (.+) \((required|optional)\): (.+)$/\1|\2|\3/' >> "$tmpfile"
    done
  done

  # Check status and display
  local installed=""
  local missing_req=""
  local missing_opt=""

  while IFS='|' read -r tool type cmd; do
    if command -v "$tool" >/dev/null 2>&1; then
      installed="$installed $tool"
    else
      if [ "$type" = "required" ]; then
        missing_req="$missing_req $tool|$cmd"
      else
        missing_opt="$missing_opt $tool|$cmd"
      fi
    fi
  done < "$tmpfile"

  # Display installed
  if [ -n "$installed" ]; then
    echo "✓ Installed:"
    for tool in $(echo "$installed" | tr ' ' '\n' | grep -v '^$' | sort); do
      echo "  ✓ $tool"
    done
    echo ""
  fi

  # Display missing required
  if [ -n "$missing_req" ]; then
    echo "✗ Missing (required):"
    for entry in $(echo "$missing_req" | tr ' ' '\n' | grep -v '^$' | sort); do
      local tool=$(echo "$entry" | cut -d'|' -f1)
      local cmd=$(echo "$entry" | cut -d'|' -f2-)
      echo "  ✗ $tool - $cmd"
    done
    echo ""
  fi

  # Display missing optional
  if [ -n "$missing_opt" ]; then
    echo "⚠ Missing (optional):"
    for entry in $(echo "$missing_opt" | tr ' ' '\n' | grep -v '^$' | sort); do
      local tool=$(echo "$entry" | cut -d'|' -f1)
      local cmd=$(echo "$entry" | cut -d'|' -f2-)
      echo "  ⚠ $tool - $cmd"
    done
    echo ""
  fi

  # Auto-install missing required tools
  if [ -n "$missing_req" ]; then
    echo "Installing missing required tools..."
    echo ""

    for entry in $(echo "$missing_req" | tr ' ' '\n' | grep -v '^$' | sort); do
      local tool=$(echo "$entry" | cut -d'|' -f1)
      local cmd=$(echo "$entry" | cut -d'|' -f2-)

      # Skip pre-installed or download-only tools
      if echo "$cmd" | grep -q "Pre-installed on macOS\|Download from"; then
        echo "⚠ $tool: $cmd"
        continue
      fi

      echo "→ Installing $tool..."
      echo "  Running: $cmd"

      # Execute installation command
      if eval "$cmd" >/dev/null 2>&1; then
        echo "  ✓ $tool installed successfully"
      else
        echo "  ✗ $tool installation failed"
      fi
      echo ""
    done

    # Re-check
    echo "Re-checking prerequisites..."
    echo ""

    local all_ok=true
    while IFS='|' read -r tool type cmd; do
      [ "$type" != "required" ] && continue
      if command -v "$tool" >/dev/null 2>&1; then
        echo "  ✓ $tool"
      else
        echo "  ✗ $tool (still missing)"
        all_ok=false
      fi
    done < "$tmpfile"
    echo ""

    rm -f "$tmpfile"

    if [ "$all_ok" = "true" ]; then
      echo "✓ All required tools installed!"
    else
      echo "⚠ Some tools still missing. Please install manually."
      return 1
    fi
  else
    echo "✓ All required tools are installed!"
    rm -f "$tmpfile"
  fi
}

case "$1" in
  --help|-h|help)
    show_help
    ;;

  init)
    init_project
    ;;

  sync)
    sync_md
    ;;

  "")
    list_tools
    ;;

  *)
    TOOL="$1"
    shift
    if [[ -x "$TOOLS_DIR/$TOOL/run.sh" ]]; then
      "$TOOLS_DIR/$TOOL/run.sh" "$@"
    else
      echo "Unknown tool: $TOOL" >&2
      echo "Run 'tools/run.sh --help' for usage" >&2
      exit 1
    fi
    ;;
esac
