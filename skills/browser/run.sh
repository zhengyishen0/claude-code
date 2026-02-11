#!/bin/bash
# Wrapper for cli.js - maintains compatibility with tool aliases
exec node "$(dirname "$0")/cli.js" "$@"
