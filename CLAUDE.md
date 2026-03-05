# claude-next-idle

## Goal

Two keyboard shortcuts for navigating Claude Code sessions:
- **`claude-next-idle`** — jump to the next session waiting for your input (LIFO). Only truly idle sessions: no fresh, no cleared, no processing.
- **`claude-next-fresh`** — jump to the next fresh/cleared session (empty prompt, nothing typed yet).

## Architecture

- `hooks/idle-signal.sh` — hook script that writes/clears signal files when sessions become idle/active/fresh
- `hooks/hooks.json` — Claude Code hook configuration (Stop, PreToolUse, PermissionRequest, PostToolUse, UserPromptSubmit, SessionStart)
- `lib/navigate.sh` — shared AppleScript navigation functions (iTerm TTY, Cursor window)
- `bin/claude-next-idle` — reads idle signal files, maintains LIFO stack, navigates to top session
- `bin/claude-next-fresh` — reads fresh signal files, maintains LIFO stack, navigates to top session
- Idle state: `~/.claude/idle-signals/<pid>` (hook-written), `~/.claude/idle-stack` (stack ordering)
- Fresh state: `~/.claude/fresh-signals/<pid>` (hook-written), `~/.claude/fresh-stack` (stack ordering)
- Debug logs at `~/claude-next-idle.log` and `~/claude-next-fresh.log` (only with `--debug`)

## Installation

```bash
# Plugin (hooks) — via marketplace
claude plugin install claude-next-idle@elias-tools

# CLI tools
./install.sh    # symlinks bin/* → ~/.local/bin/
```

## Releasing

**Automatic (CI):** Every push to `main` triggers `.github/workflows/auto-release.yml`:
1. Bumps patch version in `.claude-plugin/plugin.json`
2. Commits with `[skip ci]` to prevent loops
3. Updates version in `EliasSchlie/claude-plugins` marketplace, pushes

Just push your changes — CI handles version bumping and marketplace sync. For major/minor bumps, manually update `plugin.json` before pushing; CI increments from your number.

**Required secrets:** `APP_ID` and `APP_PRIVATE_KEY` — from the "Plugin Release Bot" GitHub App (installed on `claude-next-idle` + `claude-plugins`).

**Manual fallback:** `./release.sh` still works for local releases if CI is unavailable.

## Key Technical Decisions

### Hook-based idle detection
Hooks fire on lifecycle events to write/clear signal files (`~/.claude/idle-signals/<pid>`). No JSONL parsing needed. See [docs/session-detection.md](docs/session-detection.md).

### Block detection
Stop hook waits 1s then checks if the JSONL transcript was modified — if so, another hook blocked and the session continued (not idle). Signal is removed.

### Cleared-session exclusion (from idle)
`/clear` does NOT trigger `UserPromptSubmit` — it triggers `SessionStart` with source `clear`. A `SessionStart` hook with matcher `clear` clears the idle signal so cleared sessions don't appear idle.

### Fresh session detection
`SessionStart` (no matcher) fires on every session start (new or `/clear`) and writes a fresh signal (`~/.claude/fresh-signals/<pid>`). `UserPromptSubmit` clears both idle and fresh signals. See [docs/session-detection.md](docs/session-detection.md).

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
- **`/clear` fires `SessionStart`, not `UserPromptSubmit`** — slash commands like `/clear` are lifecycle events, not prompt submissions. Use `SessionStart` hook with appropriate matcher.
- **Async hooks omit trailing newline on stdin** — Claude Code writes JSON without `\n` for async hooks. Bash `read` returns exit code 1 on EOF without newline even though it captures the data. Always use `read ... || true`.
- **Bash 3.2** — no associative arrays, no `trap RETURN`. See [docs/macos-pitfalls.md](docs/macos-pitfalls.md#bash-32-compatibility).
- **Keyboard Maestro** — `.kmmacros` must be wrapped in a MacroGroup. See [docs/keyboard-maestro.md](docs/keyboard-maestro.md).

## Known Limitations

- **No terminal-tab-level navigation in Cursor** — raises the correct window but can't select terminal tabs
- **Block detection latency** — Stop hook waits 1s to verify, so there's a brief window where a session appears idle before block detection completes
