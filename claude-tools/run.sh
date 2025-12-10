#!/bin/bash
# Universal tool entry point
# Usage: claude-tools <tool> [command] [args...]

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"

# Show help
show_help() {
  echo "claude-tools - Universal tool entry point"
  echo ""
  echo "Usage:"
  echo "  claude-tools <tool> [command] [args...]"
  echo ""
  echo "Commands:"
  echo "  init                        Check and install all prerequisites"
  echo "  sync                        Update CLAUDE.md/AGENT.md tools section"
  echo "  diagnose                    Validate tool structure and requirements"
  echo "  setup                       Add claude-tools alias to shell"
  echo "  help, --help                Show this help message"
  echo ""
  echo "New Tool Structure:"
  echo "  claude-tools/<name>/"
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

# Diagnose tools - validate structure and requirements
diagnose() {
  echo "claude-tools diagnostic report"
  echo "=============================="
  echo ""
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
  content+="Universal entry: \`claude-tools <tool> [command] [args...]\`\n\n"

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
    content+="Run \`claude-tools $name\` for full help.\n\n"

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

# Initialize project - check and install prerequisites using Brewfile
init_project() {
  local brewfile="$TOOLS_DIR/../Brewfile"

  echo "Claude Code - Prerequisites Check"
  echo "=================================="
  echo ""

  # Check if Homebrew is installed
  if ! command -v brew >/dev/null 2>&1; then
    echo "✗ Homebrew not found"
    echo ""
    echo "Homebrew is required to install dependencies."
    echo "Install from: https://brew.sh"
    echo ""
    echo "Run this command:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    return 1
  fi

  echo "✓ Homebrew installed"
  echo ""

  # Check if Brewfile exists
  if [ ! -f "$brewfile" ]; then
    echo "✗ Brewfile not found at: $brewfile"
    return 1
  fi

  # Check current status
  echo "Checking installed dependencies..."
  echo ""

  if brew bundle check --file="$brewfile" >/dev/null 2>&1; then
    echo "✓ All dependencies are already installed!"
    echo ""
    show_versions
  else
    echo "Some dependencies are missing. Installing..."
    echo ""

    # Install missing dependencies
    if brew bundle install --file="$brewfile"; then
      echo ""
      echo "✓ Dependencies installed successfully!"
      echo ""
      show_versions

      # Remind about lockfile
      if [ -f "$TOOLS_DIR/../Brewfile.lock.json" ]; then
        echo ""
        echo "💡 Brewfile.lock.json was updated. Consider committing it:"
        echo "   git add Brewfile.lock.json"
      fi
    else
      echo ""
      echo "✗ Some dependencies failed to install"
      echo ""
      echo "Run 'brew bundle install --file=Brewfile' to see detailed errors"
      return 1
    fi
  fi
}

# Show installed versions of key tools
show_versions() {
  echo "Installed versions:"

  # Check each tool and show version
  local tools="node git chrome-cli claude"

  for tool in $tools; do
    if command -v "$tool" >/dev/null 2>&1; then
      case "$tool" in
        node)
          local version=$(node --version 2>/dev/null)
          echo "  ✓ node $version"
          ;;
        git)
          local version=$(git --version 2>/dev/null | awk '{print $3}')
          echo "  ✓ git $version"
          ;;
        chrome-cli)
          local version=$(chrome-cli version 2>/dev/null || echo "installed")
          echo "  ✓ chrome-cli $version"
          ;;
        claude)
          local version=$(claude --version 2>/dev/null | head -1 || echo "installed")
          echo "  ✓ claude $version"
          ;;
      esac
    else
      echo "  ✗ $tool (not found)"
    fi
  done
}

# Setup shell alias
setup_alias() {
  local script_path="$TOOLS_DIR/run.sh"
  local shell_rc=""

  # Detect shell and config file
  if [[ -n "$BASH_VERSION" ]]; then
    shell_rc="$HOME/.bashrc"
    [[ -f "$HOME/.bash_profile" ]] && shell_rc="$HOME/.bash_profile"
  elif [[ -n "$ZSH_VERSION" ]]; then
    shell_rc="$HOME/.zshrc"
  else
    echo "⚠ Unknown shell. Supported shells: bash, zsh"
    echo ""
    echo "Add this alias manually to your shell config:"
    echo "  alias claude-tools='$script_path'"
    return 1
  fi

  # Check if alias already exists
  if grep -q "alias claude-tools=" "$shell_rc" 2>/dev/null; then
    echo "✓ claude-tools alias already exists in $shell_rc"
    echo ""
    echo "Current alias:"
    grep "alias claude-tools=" "$shell_rc"
    return 0
  fi

  # Add alias
  echo "" >> "$shell_rc"
  echo "# claude-tools alias - auto-generated" >> "$shell_rc"
  echo "alias claude-tools='$script_path'" >> "$shell_rc"

  echo "✓ Added alias to $shell_rc"
  echo ""
  echo "Reload your shell to use the alias:"
  echo "  source $shell_rc"
  echo ""
  echo "Or start a new terminal session."
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

  diagnose)
    diagnose
    ;;

  setup)
    setup_alias
    ;;

  "")
    diagnose
    ;;

  *)
    TOOL="$1"
    shift
    if [[ -x "$TOOLS_DIR/$TOOL/run.sh" ]]; then
      "$TOOLS_DIR/$TOOL/run.sh" "$@"
    else
      echo "Unknown tool: $TOOL" >&2
      echo "Run 'claude-tools --help' for usage" >&2
      exit 1
    fi
    ;;
esac
