# claude-next-idle

## Goal

A keyboard shortcut that always brings you to the next Claude Code session waiting for your input. Each press cycles to the next one (LIFO — most recently finished first). Entering a session moves it to the back of the queue. Only truly idle sessions qualify: no fresh/unstarted sessions, no cleared sessions, no sessions still processing, no sessions whose terminal has been closed.

## Architecture

- `hooks/idle-signal.sh` — hook script that writes/clears signal files when sessions become idle/active
- `hooks/hooks.json` — Claude Code hook configuration (Stop, PreToolUse, PermissionRequest, PostToolUse, UserPromptSubmit)
- `bin/claude-next-idle` — reads signal files, maintains LIFO stack, navigates to top session
- State: `~/.claude/idle-signals/<pid>` (hook-written), `~/.claude/idle-stack` (stack ordering)
- Debug log at `~/claude-next-idle.log` (only with `--debug`)

## Installation

```bash
# Plugin (hooks) — via marketplace
claude plugin install claude-next-idle@elias-tools

# CLI tools
./install.sh    # symlinks bin/* → ~/.local/bin/
```

## Releasing

```bash
./release.sh        # auto-increments patch (1.0.1 → 1.0.2)
./release.sh 2.0.0  # explicit version
```

Bumps version in both `.claude-plugin/plugin.json` and the `EliasSchlie/claude-plugins` marketplace, commits, and pushes both repos. The marketplace has `autoUpdate: true`, so new sessions pick up changes automatically. **Always run this after pushing code changes.**

## Key Technical Decisions

### Hook-based idle detection
Hooks fire on lifecycle events to write/clear signal files (`~/.claude/idle-signals/<pid>`). No JSONL parsing needed. See [docs/session-detection.md](docs/session-detection.md).

### Block detection
Stop hook waits 1s then checks if the JSONL transcript was modified — if so, another hook blocked and the session continued (not idle). Signal is removed.

### Sub-claude exclusion
Hook checks `SUB_CLAUDE=1` env var and exits early. No sub-claude session ever writes a signal.

### Navigation
PID → TTY → iTerm AppleScript (primary). Fallback: project-name matching in window titles. See [docs/applescript.md](docs/applescript.md).

## Hard-Learned Rules

- **Never send keystrokes to Electron apps** — use `AXRaise`/`set frontmost` instead. See [docs/applescript.md](docs/applescript.md).
- **iTerm AppleScript** — match sessions by TTY (`tty of s`), not by name. See [docs/applescript.md](docs/applescript.md#iterm-applescript).
- **`pgrep` is unreliable on macOS** — use `ps -eo pid=,comm=` instead. See [docs/macos-pitfalls.md](docs/macos-pitfalls.md#pgrep-is-unreliable).
- **`grep -o 'PWD=...'` matches OLDPWD** — use `[[:space:]]PWD=` pattern. See [docs/macos-pitfalls.md](docs/macos-pitfalls.md#pwd-extraction-from-ps-eww).
- **Never modify `~/.claude/` directly** — plugin cache, `installed_plugins.json`, settings are all managed by Claude Code. Only change Git repos and let auto-update handle deployment.
- **Hooks get `$PPID` set to the claude process** — don't walk the process tree; child `claude` processes exist and `find_claude_pid()` will stop at the wrong one.
- **Async hooks omit trailing newline on stdin** — Claude Code writes JSON without `\n` for async hooks. Bash `read` returns exit code 1 on EOF without newline even though it captures the data. Always use `read ... || true`.
- **Bash 3.2** — no associative arrays, no `trap RETURN`. See [docs/macos-pitfalls.md](docs/macos-pitfalls.md#bash-32-compatibility).
- **Keyboard Maestro** — `.kmmacros` must be wrapped in a MacroGroup. See [docs/keyboard-maestro.md](docs/keyboard-maestro.md).

## Known Limitations

- **No terminal-tab-level navigation in Cursor** — raises the correct window but can't select terminal tabs
- **Block detection latency** — Stop hook waits 1s to verify, so there's a brief window where a session appears idle before block detection completes
