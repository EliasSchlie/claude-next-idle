#!/usr/bin/env bash
# Symlinks scripts from bin/ into ~/.local/bin/ so changes auto-apply.
# Safe to re-run — skips already-correct symlinks, warns on conflicts.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/.local/bin"

mkdir -p "$TARGET_DIR"

for script in "$REPO_DIR"/bin/*; do
    [ -f "$script" ] || continue
    name=$(basename "$script")
    target="$TARGET_DIR/$name"

    # Already correctly linked
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$script" ]; then
        echo "  ok  $name"
        continue
    fi

    # Conflict: file exists but isn't our symlink
    if [ -e "$target" ]; then
        echo "  !!  $name — $target already exists (not our symlink). Backing up."
        mv "$target" "${target}.bak.$(date +%s)"
    fi

    ln -s "$script" "$target"
    echo "  =>  $name → $target"
done
