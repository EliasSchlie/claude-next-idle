# claude-next-idle

macOS CLI tools for managing Claude Code sessions.

## Architecture

- `bin/claude-next-idle` — cycles through idle Claude sessions (LIFO stack)
- `bin/claude-open-cursor` — opens Cursor at the project dir of the active iTerm2 session
- `km/open-cursor-from-iterm.kmmacros` — KM macro: opens Cursor from active iTerm2 session
- State files in `~/.claude/` (idle-stack, lock dir)
- Debug log at `~/claude-next-idle.log` (only with `--debug`)

## Installation

```bash
./install.sh                            # symlinks bin/* → ~/.local/bin/
open km/open-cursor-from-iterm.kmmacros  # imports KM macro (enable the group after import)
```

- `install.sh` symlinks scripts into `~/.local/bin/`. Safe to re-run. Not managed by dotfiles `deploy.sh`.
- After importing the KM macro, enable its macro group in KM Editor.
- Once tested, merge the logic into the existing "VS code" macro: wrap its actions in an outer "If iTerm2 is active" condition.

## Key Technical Decisions

### claude-open-cursor
Gets the active iTerm session's TTY → parent shell CWD via `lsof -a -d cwd` → opens `.code-workspace` or folder in Cursor.

### Session detection
Sessions from `~/.claude/projects/**/*.jsonl`, classified by last meaningful message type (`assistant` = idle, `user` = processing). Fresh sessions (no real user messages) excluded. See [docs/session-detection.md](docs/session-detection.md).

### Process matching
Each JSONL matched to a specific live process via session ID (precise) or CWD pool (heuristic). Multiple sessions in same directory fully supported. See [docs/session-detection.md](docs/session-detection.md#process-matching).

### Sub-claude exclusion
Three layers: `SUB_CLAUDE=1` env var, `meta.json` session IDs, and `-tmp-`/`tmp.` path patterns. See [docs/session-detection.md](docs/session-detection.md#sub-claude-exclusion).

## Hard-Learned Rules

- **Never send keystrokes to Electron apps** — use `AXRaise`/`set frontmost` instead. See [docs/applescript.md](docs/applescript.md).
- **iTerm AppleScript** — match sessions by TTY (`tty of s`), not by name. See [docs/applescript.md](docs/applescript.md#iterm-applescript).
- **`pgrep` is unreliable on macOS** — use `ps -eo pid=,comm=` instead. See [docs/macos-pitfalls.md](docs/macos-pitfalls.md#pgrep-is-unreliable).
- **`grep -o 'PWD=...'` matches OLDPWD** — use `[[:space:]]PWD=` pattern. See [docs/macos-pitfalls.md](docs/macos-pitfalls.md#pwd-extraction-from-ps-eww).
- **`lsof` needs `-a` flag** for AND logic when combining `-d` and `-p`. See [docs/macos-pitfalls.md](docs/macos-pitfalls.md#lsof-gotchas).
- **Bash 3.2** — no associative arrays, no `trap RETURN`. See [docs/macos-pitfalls.md](docs/macos-pitfalls.md#bash-32-compatibility).
- **Keyboard Maestro** — `.kmmacros` must be wrapped in a MacroGroup. See [docs/keyboard-maestro.md](docs/keyboard-maestro.md).

## Known Limitations

- **No terminal-tab-level navigation in Cursor** — raises the correct window but can't select terminal tabs
- **Streaming responses appear idle** — during generation, JSONL shows `type=assistant` momentarily
- **Same-CWD navigation imprecision** — PID→JSONL pairing is heuristic; cycling fixes mismatches
- **Post-/clear stale JSONL** — old JSONL retains messages; appears idle until its process exits
