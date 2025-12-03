#!/bin/bash
# chrome-cli-plus - Enhanced chrome-cli with React/SPA support
# Usage: chrome-cli-plus <command> [args...]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "$1" in
  recon|r)
    # Get page structure in markdown
    # Usage: chrome-cli-plus recon [--status] [--section <name>]
    # --status: Also show loading status of key elements
    # --section: Filter to specific section (header, nav, main, aside, footer, article, section, form)
    shift # remove 'recon'

    STATUS=""
    SECTION=""

    while [ $# -gt 0 ]; do
      case "$1" in
        --status|-s)
          STATUS="true"
          shift
          ;;
        --section|-S)
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

    sleep 1

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
      OUTPUT=$(chrome-cli execute "$(cat "$SCRIPT_DIR/html2md.js")")
      # Print header (title, URL, ---, blank line)
      echo "$OUTPUT" | head -n 4
      # Extract section: from "## SectionName" (or "## SectionName: label") until next "## "
      echo "$OUTPUT" | awk -v sec="$SECTION_CAP" '
        /^## / {
          if (p) exit
          # Match "## Nav" or "## Nav: something"
          if ($0 ~ "^## " sec "($|:)") p=1
        }
        p { print }
      '
    else
      chrome-cli execute "$(cat "$SCRIPT_DIR/html2md.js")"
    fi
    ;;

  open|o)
    # Open URL and recon (waits 1s by default)
    # Usage: chrome-cli-plus open "URL" [--status]
    URL=$2
    if [ -z "$URL" ]; then
      echo "Usage: chrome-cli-plus open \"URL\" [--status]" >&2
      exit 1
    fi
    chrome-cli open "$URL"
    if [ "$3" = "--status" ]; then
      "$0" recon --status
    else
      "$0" recon
    fi
    ;;

  wait|w)
    # Wait for page to load
    # Usage: chrome-cli-plus wait [timeout] [selector]
    TIMEOUT=${2:-10}
    SELECTOR=${3:-""}
    elapsed=0
    interval=0.3
    while [ "$elapsed" -lt "$TIMEOUT" ]; do
      if [ -n "$SELECTOR" ]; then
        result=$(chrome-cli execute "document.querySelector('$SELECTOR') ? 'ready' : 'loading'")
      else
        result=$(chrome-cli execute "document.readyState")
      fi
      if [ "$result" = "complete" ] || [ "$result" = "ready" ]; then
        exit 0
      fi
      sleep $interval
      elapsed=$((elapsed + 1))
    done
    echo "Timeout waiting for page to load" >&2
    exit 1
    ;;

  click|c)
    # Click element with multiple selector strategies
    # Usage: chrome-cli-plus click "CSS_SELECTOR"
    #        chrome-cli-plus click --text "Button Text"
    #        chrome-cli-plus click --aria "aria-label text"
    #        chrome-cli-plus click --testid "data-testid value"
    #        Add --wait to wait for DOM changes after click
    shift # remove 'click'

    SELECTOR=""
    TEXT=""
    ARIA=""
    TESTID=""
    WAIT=""

    while [ $# -gt 0 ]; do
      case "$1" in
        --text|-t)
          TEXT="$2"
          shift 2
          ;;
        --aria|-a)
          ARIA="$2"
          shift 2
          ;;
        --testid|-d)
          TESTID="$2"
          shift 2
          ;;
        --wait|-w)
          WAIT="true"
          shift
          ;;
        -*)
          echo "Unknown option: $1" >&2
          exit 1
          ;;
        *)
          SELECTOR="$1"
          shift
          ;;
      esac
    done

    # Escape double quotes in values for JS string literals
    SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed 's/"/\\"/g')
    TEXT_ESC=$(printf '%s' "$TEXT" | sed 's/"/\\"/g')
    ARIA_ESC=$(printf '%s' "$ARIA" | sed 's/"/\\"/g')
    TESTID_ESC=$(printf '%s' "$TESTID" | sed 's/"/\\"/g')

    # Read JS file
    JS_CODE=$(cat "$SCRIPT_DIR/click-element.js")

    # Execute with _p variable (avoid 'options' which causes issues)
    result=$(chrome-cli execute 'var _p={selector:"'"$SELECTOR_ESC"'",text:"'"$TEXT_ESC"'",aria:"'"$ARIA_ESC"'",testid:"'"$TESTID_ESC"'"}; '"$JS_CODE")
    echo "$result"

    # If --wait, poll for DOM stability
    if [ "$WAIT" = "true" ]; then
      sleep 0.5
      # Wait up to 2 seconds for DOM to settle
      for i in 1 2 3 4; do
        sleep 0.5
      done
    fi
    ;;

  input|i)
    # Set input value with React-compatible events
    # Usage: chrome-cli-plus input "CSS_SELECTOR" "VALUE" [--clear] [--type]
    #        --clear: Clear existing value before setting
    #        --type: Type character-by-character (slower but more compatible)
    shift # remove 'input'

    SELECTOR=""
    VALUE=""
    CLEAR="false"
    TYPE="false"

    # First positional arg is selector, second is value
    POSITIONAL_COUNT=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --clear|-c)
          CLEAR="true"
          shift
          ;;
        --type|-t)
          TYPE="true"
          shift
          ;;
        -*)
          echo "Unknown option: $1" >&2
          exit 1
          ;;
        *)
          if [ $POSITIONAL_COUNT -eq 0 ]; then
            SELECTOR="$1"
            POSITIONAL_COUNT=1
          elif [ $POSITIONAL_COUNT -eq 1 ]; then
            VALUE="$1"
            POSITIONAL_COUNT=2
          fi
          shift
          ;;
      esac
    done

    if [ -z "$SELECTOR" ] || [ -z "$VALUE" ]; then
      echo "Usage: chrome-cli-plus input \"SELECTOR\" \"VALUE\" [--clear] [--type]" >&2
      exit 1
    fi

    # Escape double quotes in values for JS string literals
    SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed 's/"/\\"/g')
    VALUE_ESC=$(printf '%s' "$VALUE" | sed 's/"/\\"/g')

    # Read JS file
    JS_CODE=$(cat "$SCRIPT_DIR/set-input.js")

    # Execute with _p variable (avoid 'options' which causes issues)
    result=$(chrome-cli execute 'var _p={selector:"'"$SELECTOR_ESC"'",value:"'"$VALUE_ESC"'",clear:'"$CLEAR"'}; '"$JS_CODE")
    echo "$result"
    ;;

  tabs|t)
    # List all tabs
    chrome-cli list tabs
    ;;

  info)
    # Current tab info
    chrome-cli info
    ;;

  close)
    # Close tab by ID or active tab
    # Usage: chrome-cli-plus close [TAB_ID]
    if [ -n "$2" ]; then
      chrome-cli close -t "$2"
    else
      chrome-cli close
    fi
    ;;

  help|h|--help|-h)
    echo "chrome-cli-plus - Enhanced chrome-cli with React/SPA support"
    echo ""
    echo "Commands:"
    echo "  recon, r [--status] [-S x] Get page structure (waits 1s)"
    echo "                             --status/-s: show loading info"
    echo "                             --section/-S: filter to section (header, nav, main,"
    echo "                               aside, footer, article, section, form)"
    echo "  open, o URL [--status]     Open URL and recon (--status shows load info)"
    echo "  wait, w [timeout] [sel]    Wait for page load (polling)"
    echo "  click, c SELECTOR          Click by CSS selector"
    echo "  click --text TEXT          Click by visible text (partial, case-insensitive)"
    echo "  click --aria LABEL         Click by aria-label (partial, case-insensitive)"
    echo "  click --testid ID          Click by data-testid (exact match)"
    echo "  click ... --wait           Wait for DOM changes after click"
    echo "  input, i SEL VAL           Set input value"
    echo "  input SEL VAL --clear      Clear first, then set value"
    echo "  input SEL VAL --type       Type char-by-char (more compatible)"
    echo "  tabs, t                    List all tabs"
    echo "  info                       Current tab info"
    echo "  close [TAB_ID]             Close tab"
    echo ""
    echo "Click Examples:"
    echo "  chrome-cli-plus click \"button.submit\""
    echo "  chrome-cli-plus click --text \"Add to wishlist\""
    echo "  chrome-cli-plus click --aria \"Close dialog\""
    echo "  chrome-cli-plus click --testid \"submit-btn\" --wait"
    echo ""
    echo "Input Examples:"
    echo "  chrome-cli-plus input \"#email\" \"test@example.com\""
    echo "  chrome-cli-plus input \"#search\" \"query\" --clear"
    echo "  chrome-cli-plus input \"#field\" \"value\" --clear --type"
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run 'chrome-cli-plus help' for usage" >&2
    exit 1
    ;;
esac
