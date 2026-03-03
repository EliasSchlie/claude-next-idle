#!/usr/bin/env bash
# Symlinks bin/* → ~/.local/bin/ for CLI tools.
# The plugin (hooks) is installed via the marketplace:
#   claude plugin install claude-next-idle@elias-tools
#
# Safe to re-run — skips already-correct symlinks, warns on conflicts.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"

mkdir -p "$BIN_DIR"

for script in "$REPO_DIR"/bin/*; do
    [ -f "$script" ] || continue
    name=$(basename "$script")
    target="$BIN_DIR/$name"

    if [ -L "$target" ] && [ "$(readlink "$target")" = "$script" ]; then
        echo "  ok  $name"
        continue
    fi

    if [ -e "$target" ]; then
        echo "  !!  $name — $target already exists (not our symlink). Backing up."
        mv "$target" "${target}.bak.$(date +%s)"
    fi

    ln -s "$script" "$target"
    echo "  =>  $name → $target"
done
