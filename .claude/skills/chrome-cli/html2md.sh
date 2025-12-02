#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
chrome-cli execute "$(cat "$SCRIPT_DIR/html2md.js")"
