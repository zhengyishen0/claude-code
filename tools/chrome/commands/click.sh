#!/bin/bash
# click.sh - Click element by CSS selector
# Usage: click.sh "selector"

if [[ "$1" == "--help" ]]; then
  echo "click SELECTOR          Click element by CSS selector"
  echo ""
  echo "Examples:"
  echo "  click '[data-testid=\"search-button\"]'"
  echo "  click '#submit-btn'"
  echo "  click '[aria-label=\"Search\"]'"
  echo "  click 'button.primary'"
  echo ""
  echo "Chain with wait/recon as needed:"
  echo "  click '...' + wait + recon"
  echo "  click '...' + wait '[role=dialog]' + recon"
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."
[ -f "$SCRIPT_DIR/config" ] && source "$SCRIPT_DIR/config"

SELECTOR="$1"
if [ -z "$SELECTOR" ]; then
  echo "Usage: click 'CSS selector'" >&2
  exit 1
fi

# Escape selector for JS
SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed "s/'/\\\\'/g")

# Click the element
result=$(chrome-cli execute "
(function() {
  var el = document.querySelector('$SELECTOR_ESC');
  if (!el) return 'FAIL: element not found';

  // Only scroll if element is not in viewport
  var rect = el.getBoundingClientRect();
  var isVisible = (
    rect.top >= 0 &&
    rect.left >= 0 &&
    rect.bottom <= (window.innerHeight || document.documentElement.clientHeight) &&
    rect.right <= (window.innerWidth || document.documentElement.clientWidth)
  );

  if (!isVisible) {
    el.scrollIntoView({block: 'center', behavior: 'instant'});
  }

  el.click();
  var tag = el.tagName.toLowerCase();
  var text = (el.innerText || '').trim().substring(0, 30);
  return 'OK: clicked ' + tag + (text ? ' \"' + text + '\"' : '');
})()
")

echo "$result"

if [[ "$result" == FAIL* ]]; then
  exit 1
fi
