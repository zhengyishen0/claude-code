#!/bin/bash
# close.sh - Close tab by ID or active tab
# Usage: close.sh [TAB_ID]

if [[ "$1" == "--help" ]]; then
  echo "close [TAB_ID]              Close tab (active if no ID given)"
  exit 0
fi

if [ -n "$1" ]; then
  chrome-cli close -t "$1"
else
  chrome-cli close
fi
