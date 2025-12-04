#!/bin/bash
# tabs.sh - List all tabs
# Usage: tabs.sh

if [[ "$1" == "--help" ]]; then
  echo "tabs                        List all open tabs"
  exit 0
fi

chrome-cli list tabs
