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

### claude-open-cursor (TTY → shell CWD → Cursor)
- Gets the active iTerm session's TTY → parent shell CWD via `lsof -a -d cwd`
- Opens `.code-workspace` file if one exists in the directory, otherwise opens the folder

### Session detection (JSONL-based)
- Sessions are detected from `~/.claude/projects/**/*.jsonl` files
- Last meaningful message type determines status: `assistant` = idle, `user` = processing
- Must skip noise types: `system`, `progress`, `file-history-snapshot`, `pr-link` — these get appended AFTER the assistant finishes
- `tail -50` is needed because busy sessions can have many trailing noise entries
- CWD is extracted from the first 10 lines of the JSONL (early `user` type messages contain `cwd` field)
- Single python3 call per session (combined CWD + status check) for performance

### Closed session filtering (two layers)
1. **Idle sessions**: Require a live claude process whose `PWD` env var matches the JSONL `cwd` (OR session ID in tasks/ via lsof)
   - `PWD` is the shell CWD at launch time — matches the JSONL project directory
   - Only shell-parented claude processes are checked (filters out tmux-spawned sub-claudes/workers)
2. **Processing sessions**: Require session ID to appear in `lsof .claude/tasks/` of a running process
   - Without this check, closed sessions with unsent responses appear permanently stuck
- **Known limitation**: Multiple JSONL files for the same CWD (old sessions within 120-min window) all appear alive if any process matches that CWD

### Sub-claude exclusion (three layers)
1. **Running processes**: `ps eww -p PID | grep SUB_CLAUDE=1` — checks env var on running claude processes
2. **meta.json**: `~/.sub-claude/pools/*/jobs/*/meta.json` → `claude_session_id` field
3. **Path pattern**: JSONL project dirs containing `-tmp-` or `tmp.` (worktree sessions)
- Layers 1+2 catch sub-claude agents in real project dirs; layer 3 catches worktree-based agents

### PID → session ID mapping
- `lsof -p PID | grep .claude/tasks/` → the directory basename IS the session UUID
- NOT all claude processes have tasks/ open — only those with active task tracking
- Cannot use process CWD (always `/` for Node.js processes)
- Cannot use `lsof | grep .jsonl` (files opened/closed per write, not kept open)

## Hard-Learned Rules

### NEVER send synthetic keystrokes to Electron apps
- AppleScript `keystroke` commands to Cursor/VS Code are fundamentally broken:
  - Keystrokes arrive at whatever window has focus, which may change during execution
  - Command palette automation (`Cmd+Shift+P` → type command → Enter) fails catastrophically — activates random features, resizes windows, triggers system shortcuts
  - Timing-dependent (delay between keystrokes is unreliable)
- **Safe operations**: `AXRaise` (raise window), `set frontmost` (activate app) — these use accessibility API, not keyboard simulation
- **For terminal tab switching in Cursor**: Only reliable path is a VS Code extension exposing a `focusTerminalByName` command. Accessibility tree for Electron is too opaque for tab-level navigation.

### iTerm AppleScript
- iTerm has proper AppleScript dictionary (`select`, `set index`)
- Use `set index of w to 1` to bring window to front + `select t` for tab
- Session `name` property contains the terminal title (usually shows running command or CWD)

### Keyboard Maestro integration
- KM shell scripts run in minimal env — must set PATH explicitly in script
- Hotkeys with Ctrl+Cmd+Option may conflict with macOS system shortcuts
- See [docs/keyboard-maestro.md](docs/keyboard-maestro.md) for creating `.kmmacros` files programmatically

### lsof on macOS
- **Always use `-a` flag** when combining `-d` and `-p` — without it, lsof uses OR logic (returns ALL processes with that fd type, not just the specified PID)
- `lsof -a -d cwd -p $PID -Fn` → correctly gets CWD for a single process
- Claude Node.js process CWD is always `/` — use parent shell's CWD or PWD env var instead
- `lsof .claude/tasks/` approach: NOT all Claude processes have tasks/ open

### Bash 3.2 compatibility (macOS default)
- No associative arrays (`local -A` fails)
- No `trap ... RETURN` (silently ignored, leaks temp files)
- Use `grep -F` with temp files instead of associative arrays
- Use explicit `rm -f` instead of RETURN traps

## Known Limitations

- **No terminal-tab-level navigation in Cursor** — raises the correct window but can't select the right terminal tab within it
- **Streaming responses appear idle** — during active generation, JSONL shows `type=assistant`, making the session look idle momentarily
- **iTerm session matching** — matches by project name in session title; if Claude doesn't set the terminal title to include the project name, matching may fail

## Future: VS Code Extension
The only reliable way to switch terminal tabs in Cursor is a VS Code extension that:
1. Listens for a command (e.g., `claude-next-idle.focusTerminal`)
2. Accepts a session ID or project name
3. Iterates `vscode.window.terminals`, finds the match, calls `terminal.show()`
This would replace the AppleScript navigation entirely for Cursor sessions.
