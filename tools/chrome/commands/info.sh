#!/bin/bash
# info.sh - Current tab info
# Usage: info.sh

if [[ "$1" == "--help" ]]; then
  echo "info                        Current tab info (title, URL, ID)"
  exit 0
fi

chrome-cli info
