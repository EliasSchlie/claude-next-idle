#!/usr/bin/env bash
# Installs claude-next-idle:
#   1. Symlinks bin/* → ~/.local/bin/ (CLI tools)
#   2. Copies plugin (hooks + manifest) → ~/.local/share/claude-next-idle/
#
# Safe to re-run — skips already-correct symlinks, warns on conflicts.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
PLUGIN_DIR="$HOME/.local/share/claude-next-idle"

# --- bin/ symlinks ---

mkdir -p "$BIN_DIR"

echo "CLI tools:"
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

# --- plugin (hooks + manifest) ---

echo ""
echo "Plugin:"
mkdir -p "$PLUGIN_DIR/hooks" "$PLUGIN_DIR/.claude-plugin"

for f in hooks/hooks.json hooks/idle-signal.sh; do
    src="$REPO_DIR/$f"
    dst="$PLUGIN_DIR/$f"
    [ -f "$src" ] || continue
    if [ -f "$dst" ] && diff -q "$src" "$dst" >/dev/null 2>&1; then
        echo "  ok  $f"
    else
        cp "$src" "$dst"
        echo "  =>  $f"
    fi
done

# Plugin manifest
src="$REPO_DIR/.claude-plugin/plugin.json"
dst="$PLUGIN_DIR/.claude-plugin/plugin.json"
if [ -f "$dst" ] && diff -q "$src" "$dst" >/dev/null 2>&1; then
    echo "  ok  .claude-plugin/plugin.json"
else
    cp "$src" "$dst"
    echo "  =>  .claude-plugin/plugin.json"
fi

chmod +x "$PLUGIN_DIR/hooks/idle-signal.sh"

echo ""
echo "Done. Add to ~/.claude/settings.json hooks to enable (see hooks/hooks.json)."
