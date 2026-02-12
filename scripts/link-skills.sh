#!/usr/bin/env bash
# link-skills.sh - Auto-discover skills and create symlinks in bin/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BIN_DIR="$SCRIPT_DIR/bin"
SKILLS_DIR="$PROJECT_DIR/skills"

# Clear and recreate bin/
rm -rf "$BIN_DIR"
mkdir -p "$BIN_DIR"

# Link cc.sh
ln -sf ../cc.sh "$BIN_DIR/cc"

# Auto-discover skills with `run` entry point
count=1
for skill_run in "$SKILLS_DIR"/*/run; do
    [[ -f "$skill_run" ]] || continue
    skill_name=$(basename "$(dirname "$skill_run")")
    ln -sf "$skill_run" "$BIN_DIR/$skill_name"
    ((count++))
done

echo "Linked $count commands to scripts/bin/"
ls "$BIN_DIR" | sed 's/^/  /'
