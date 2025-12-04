#!/bin/bash
# wait.sh - Wait for DOM changes or specific elements
# Usage: wait.sh [selector] [--timeout|-T N] [--gone] [--section|-S SECTION]
#
# Examples:
#   wait.sh              # Wait for any DOM change (5s default)
#   wait.sh ".modal"     # Wait for .modal to appear (5s default)
#   wait.sh ".modal" -T 10  # Wait up to 10s for .modal
#   wait.sh ".loading" --gone  # Wait for .loading to disappear
#   wait.sh ".btn" -S "Provide feedback"  # Wait in specific section

TIMEOUT=5
SELECTOR=""
GONE=false
SECTION=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout|-T) TIMEOUT="$2"; shift 2 ;;
    --gone) GONE=true; shift ;;
    --section|-S) SECTION="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) SELECTOR="$1"; shift ;;
  esac
done

interval=0.5
elapsed=0

# Build JS for finding root element (section scoping)
SECTION_ESC=$(printf '%s' "$SECTION" | sed 's/"/\\"/g')
FIND_ROOT_JS='
(function() {
  var section = "'"$SECTION_ESC"'";
  if (!section) return document;
  var sectionLower = section.toLowerCase();

  // Strategy 1: Match aria-label on semantic containers only
  var containers = document.querySelectorAll("dialog,[role=dialog],section,article,form,header,main,nav,aside,footer");
  for (var i = 0; i < containers.length; i++) {
    var label = (containers[i].getAttribute("aria-label") || "").toLowerCase();
    if (label && label.indexOf(sectionLower) > -1) return containers[i];
  }

  // Strategy 2: Match heading text
  var headings = document.querySelectorAll("h1,h2,h3,h4,h5,h6");
  for (var i = 0; i < headings.length; i++) {
    var hText = (headings[i].textContent || "").toLowerCase();
    if (hText.indexOf(sectionLower) > -1) {
      return headings[i].closest("dialog,[role=dialog],section,article,form,header,main,nav,aside,footer") || headings[i].parentElement;
    }
  }

  // Strategy 3: Direct selector
  return document.querySelector(section) || document;
})()
'

if [ -n "$SELECTOR" ]; then
  # Wait for specific selector to appear/disappear (within section if specified)
  while (( $(echo "$elapsed < $TIMEOUT" | bc -l) )); do
    if [ "$GONE" = true ]; then
      result=$(chrome-cli execute "var root = $FIND_ROOT_JS; root.querySelector('$SELECTOR') ? 'exists' : 'gone'")
      if [ "$result" = "gone" ]; then
        echo "OK: $SELECTOR disappeared"
        exit 0
      fi
    else
      result=$(chrome-cli execute "var root = $FIND_ROOT_JS; root.querySelector('$SELECTOR') ? 'found' : 'waiting'")
      if [ "$result" = "found" ]; then
        echo "OK: $SELECTOR found"
        exit 0
      fi
    fi
    sleep $interval
    elapsed=$(echo "$elapsed + $interval" | bc)
  done
  echo "TIMEOUT: $SELECTOR not $( [ "$GONE" = true ] && echo 'gone' || echo 'found' ) after ${TIMEOUT}s" >&2
  exit 1
else
  # Wait for any DOM change using MutationObserver
  # Inject observer, wait for mutation or timeout
  JS_OBSERVER='
(function() {
  return new Promise(function(resolve) {
    var resolved = false;
    var observer = new MutationObserver(function() {
      if (!resolved) {
        resolved = true;
        observer.disconnect();
        resolve("changed");
      }
    });
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      characterData: true
    });
    setTimeout(function() {
      if (!resolved) {
        resolved = true;
        observer.disconnect();
        resolve("timeout");
      }
    }, '"$((TIMEOUT * 1000))"');
  });
})()
'
  # chrome-cli doesn't support async, so we poll for changes instead
  # Take snapshot, then compare
  SNAPSHOT=$(chrome-cli execute "document.body.innerHTML.length + '|' + document.querySelectorAll('*').length")

  while (( $(echo "$elapsed < $TIMEOUT" | bc -l) )); do
    sleep $interval
    elapsed=$(echo "$elapsed + $interval" | bc)
    CURRENT=$(chrome-cli execute "document.body.innerHTML.length + '|' + document.querySelectorAll('*').length")
    if [ "$CURRENT" != "$SNAPSHOT" ]; then
      echo "OK: DOM changed"
      exit 0
    fi
  done
  echo "OK: No DOM change (stable)"
  exit 0
fi
