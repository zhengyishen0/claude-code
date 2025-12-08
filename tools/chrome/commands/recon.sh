#!/bin/bash
# recon.sh - Get page structure in markdown
# Usage: recon.sh [--status]

if [[ "$1" == "--help" ]]; then
  echo "recon [--status]  Get page structure as markdown"
  echo "  --status: show loading info (images, scripts, etc.)"
  echo ""
  echo "Filter output with grep/awk:"
  echo "  Show Nav:    recon | awk '/^## Nav(\$|:)/,/^## [^N]/'"
  echo "  Show Main:   recon | awk '/^## Main(\$|:)/,/^## [^M]/'"
  echo "  Show Dialog: recon | awk '/^## Dialog/,/^## [^D]/'"
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."

STATUS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --status)
      STATUS="true"
      shift
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

chrome-cli execute "$(cat "$SCRIPT_DIR/js/html2md.js")"
