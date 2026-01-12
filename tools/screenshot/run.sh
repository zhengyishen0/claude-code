#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Show help if no args
if [ $# -eq 0 ]; then
  cat << 'EOF'
screenshot - Background window capture for macOS

USAGE
  screenshot <app_name> [output_path]
  screenshot <app_name> --all
  screenshot --list

DESCRIPTION
  Captures screenshots of windows without activating them using macOS
  window server APIs. Useful for capturing browser automation,
  monitoring background processes, or documentation.

ARGUMENTS
  app_name      Application name to capture (case-insensitive partial match)
                Examples: "Chrome", "Google Chrome", "Terminal"

  output_path   Optional output file path (default: ./tmp/screenshot-TIMESTAMP.png)

OPTIONS
  --list        List all capturable windows with IDs and titles
  --all         Capture all windows matching app_name (outputs multiple files)

EXAMPLES
  # Capture Chrome window to default location
  screenshot "Google Chrome"

  # Capture with specific output path
  screenshot Chrome /tmp/my-screenshot.png

  # Capture all Chrome windows (active tab in each window)
  screenshot Chrome --all

  # List all windows
  screenshot --list

TECHNICAL NOTES
  - Uses PyObjC + Quartz framework to get CGWindowIDs
  - Captures via native screencapture CLI (no activation required)
  - Matches first window containing app_name (case-insensitive)
  - Output format: PNG (lossless)

REQUIREMENTS
  - macOS only
  - Python 3 with pyobjc-framework-Quartz

EOF
  exit 0
fi

# Run the Python capture script
python3 "$SCRIPT_DIR/capture.py" "$@"
