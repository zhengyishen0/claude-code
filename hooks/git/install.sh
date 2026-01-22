#!/bin/bash
# hooks/git/install.sh
# Set core.hooksPath so git hooks work in all worktrees

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting core.hooksPath to: $SCRIPT_DIR"
git config core.hooksPath "$SCRIPT_DIR"

echo "Done. Git hooks will now run from $SCRIPT_DIR for all worktrees."
