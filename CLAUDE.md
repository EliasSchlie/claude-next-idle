# claude-next-idle

macOS CLI tool. Cycles through idle Claude Code sessions via a LIFO stack, triggered by a Keyboard Maestro shortcut.

## Architecture

- `bin/claude-next-idle` — single bash script, macOS-only
- State files in `~/.claude/` (idle-stack, lock dir)
- Debug log at `~/claude-next-idle.log` (only with `--debug`)

## Key Technical Decisions

### Session detection (JSONL-based)
- Sessions are detected from `~/.claude/projects/**/*.jsonl` files
- Last meaningful message type determines status: `assistant` = idle, `user` = processing
- Must skip noise types: `system`, `progress`, `file-history-snapshot`, `pr-link` — these get appended AFTER the assistant finishes
- `tail -50` is needed because busy sessions can have many trailing noise entries
- CWD is extracted from the first 10 lines of the JSONL (early `user` type messages contain `cwd` field)
- Single python3 call per session (combined CWD + status check) for performance

### Ghost session prevention
- Sessions with `type=user` as last entry are only counted as "processing" if they have a live claude process (verified via `lsof .claude/tasks/` mapping)
- Without this check, closed sessions with unsent responses appear permanently stuck as "processing"

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
- `open file.kmmacros` imports the macro but does NOT enable the macro group — user must enable manually
- KM modifier values: Command=256, Shift=512, Option=2048, Control=4096
- Hotkeys that include Ctrl+Cmd+Option may conflict with macOS system shortcuts (window management, accessibility)

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
