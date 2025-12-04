#!/bin/bash
# close.sh - Close tab by ID or active tab
# Usage: close.sh [TAB_ID]

if [ -n "$1" ]; then
  chrome-cli close -t "$1"
else
  chrome-cli close
fi
