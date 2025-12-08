#!/bin/bash
# input.sh - Set input value by CSS selector
# Usage: input.sh "selector" "value"

SCRIPT_DIR="$(dirname "$0")/.."
[ -f "$SCRIPT_DIR/config" ] && source "$SCRIPT_DIR/config"

SELECTOR="$1"
VALUE="$2"

if [ -z "$SELECTOR" ] || [ -z "$VALUE" ]; then
  echo "Usage: input 'CSS selector' 'value'" >&2
  exit 1
fi

# Escape for JS
SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed "s/'/\\\\'/g")
VALUE_ESC=$(printf '%s' "$VALUE" | sed "s/'/\\\\'/g")

# Set input value (React-safe)
result=$(chrome-cli execute "
(function() {
  var el = document.querySelector('$SELECTOR_ESC');
  if (!el) return 'FAIL: element not found';

  el.focus();
  el.click();

  // Use native setter for React compatibility
  var proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement : HTMLInputElement;
  var setter = Object.getOwnPropertyDescriptor(proto.prototype, 'value');
  if (setter && setter.set) {
    setter.set.call(el, '$VALUE_ESC');
  } else {
    el.value = '$VALUE_ESC';
  }

  // Dispatch events React listens to
  el.dispatchEvent(new Event('input', {bubbles: true}));
  el.dispatchEvent(new Event('change', {bubbles: true}));

  var tag = el.tagName.toLowerCase();
  return 'OK: set ' + tag + ' = \"' + '$VALUE_ESC'.substring(0, 20) + '\"';
})()
")

echo "$result"

if [[ "$result" == FAIL* ]]; then
  exit 1
fi
