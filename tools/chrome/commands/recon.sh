#!/bin/bash
# recon.sh - Get page structure in markdown
# Usage: recon.sh [--status] [--section <name>]

if [[ "$1" == "--help" ]]; then
  echo "recon [--status] [--section SECTION]  Get page structure as markdown"
  echo "  --status: show loading info (images, scripts, etc.)"
  echo "  --section: filter to section (header, nav, main, aside, footer)"
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."

STATUS=""
SECTION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --status)
      STATUS="true"
      shift
      ;;
    --section)
      SECTION="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      shift
      ;;
  esac
done

if [ "$STATUS" = "true" ]; then
  chrome-cli execute "
    const status = {
      readyState: document.readyState,
      images: { total: document.images.length, loaded: Array.from(document.images).filter(i => i.complete).length },
      scripts: { total: document.scripts.length },
      iframes: document.querySelectorAll('iframe').length,
      pendingXHR: window.performance.getEntriesByType('resource').filter(r => !r.responseEnd).length
    };
    '## Loading Status\\n' +
    '- Document: ' + status.readyState + '\\n' +
    '- Images: ' + status.images.loaded + '/' + status.images.total + ' loaded\\n' +
    '- Scripts: ' + status.scripts.total + '\\n' +
    '- Iframes: ' + status.iframes + '\\n' +
    '- Pending resources: ' + status.pendingXHR + '\\n\\n';
  "
fi

if [ -n "$SECTION" ]; then
  # Capitalize first letter: nav → Nav
  SECTION_CAP="$(echo "$SECTION" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
  # Get full output, extract header (first 4 lines) and filtered section
  OUTPUT=$(chrome-cli execute "$(cat "$SCRIPT_DIR/js/html2md.js")")
  # Print header (title, URL, ---, blank line)
  echo "$OUTPUT" | head -n 4
  # Extract section: from "## SectionName" until the next section at same level
  # For Dialog, include nested ## sections until we hit a non-dialog section
  echo "$OUTPUT" | awk -v sec="$SECTION_CAP" '
    /^## / {
      if ($0 ~ "^## " sec "($|:)") { p=1; inDialog=(sec=="Dialog") }
      else if (p) {
        # If in dialog, skip nested sections (Header, Footer, Section inside dialog)
        if (inDialog && ($0 ~ "^## (Header|Footer|Section|Form)($|:)")) { next }
        exit
      }
    }
    p { print }
  '
else
  chrome-cli execute "$(cat "$SCRIPT_DIR/js/html2md.js")"
fi
