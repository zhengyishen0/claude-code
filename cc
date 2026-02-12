#!/usr/bin/env bash
# cc - Shared Claude wrapper for all scripts in this project
# Usage: cc [claude args...]
#
# Interactive use: source env.sh (defines cc as a shell function with resume support)
# Script use:      ~/.claude-code/cc -p "prompt" --model claude-opus-4-5
exec claude "$@" --allow-dangerously-skip-permissions
