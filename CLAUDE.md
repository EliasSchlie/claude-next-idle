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
- CWD is extracted from the first 30 lines of the JSONL (early `user` type messages contain `cwd` field)
- Single python3 call for ALL sessions (batched) — parses JSONLs + matches to live processes
- Fresh sessions (no real user message) excluded: `type=user` entries with content starting with `<` are system-generated

### Closed session filtering (session→process matching)
- Each JSONL is matched to a specific live claude process via two methods:
  1. **Session ID match**: `lsof tasks/` gives session UUID → precise PID mapping
  2. **CWD pool matching**: Group processes by PWD, group JSONLs by `cwd` field. For each CWD, the N most recent JSONLs get the N available processes (by mtime descending). Excess JSONLs = dead sessions.
- Sessions without a matching live process are excluded (dead/closed)
- **Multiple sessions in same directory**: Fully supported. Each gets its own process from the CWD pool.

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

### pgrep on macOS is unreliable
- `pgrep -x claude` silently misses some processes — verified with 13 processes, pgrep returned only 12
- **Use `ps -eo pid=,comm= | awk '$2 == "claude"'` instead** — reliable across all processes
- No known workaround for pgrep; the miss is consistent and reproducible

### PWD extraction from `ps eww` output
- `grep -o 'PWD=[^ ]*'` matches OLDPWD too! `OLDPWD=/Users/mee` contains substring `PWD=/Users/mee`
- **Use `grep -oE '[[:space:]]PWD=[^[:space:]]+'`** — requires space before PWD, excluding OLDPWD
- PWD may not match the JSONL project directory if claude determines the project independently of launch CWD (e.g., session resume from a different directory)

### lsof on macOS
- **Always use `-a` flag** when combining `-d` and `-p` — without it, lsof uses OR logic (returns ALL processes with that fd type, not just the specified PID)
- `lsof -a -d cwd -p $PID -Fn` → correctly gets CWD for a single process
- Claude Node.js process CWD is always `/` — use parent shell's CWD or PWD env var instead
- `lsof .claude/tasks/` approach: NOT all Claude processes have tasks/ open
- JSONL files are opened/closed per write — cannot use lsof to catch PID→JSONL mapping

### Bash 3.2 compatibility (macOS default)
- No associative arrays (`local -A` fails)
- No `trap ... RETURN` (silently ignored, leaks temp files)
- Use `grep -F` with temp files instead of associative arrays
- Use explicit `rm -f` instead of RETURN traps

## Known Limitations

- **No terminal-tab-level navigation in Cursor** — raises the correct window but can't select the right terminal tab within it
- **Streaming responses appear idle** — during active generation, JSONL shows `type=assistant`, making the session look idle momentarily
- **iTerm session matching** — matches by project name in session title; if Claude doesn't set the terminal title to include the project name, matching may fail
- **Same-CWD navigation imprecision** — when multiple sessions share a CWD, the PID→JSONL pairing within that CWD is heuristic (by mtime). Navigation may land on the wrong terminal of the same project; cycling fixes this.
- **Post-/clear sessions** — after `/clear`, the JSONL still contains old real-user messages, so the session appears idle (not fresh). Needs a `/clear` marker detection to fix.

## Future: VS Code Extension
The only reliable way to switch terminal tabs in Cursor is a VS Code extension that:
1. Listens for a command (e.g., `claude-next-idle.focusTerminal`)
2. Accepts a session ID or project name
3. Iterates `vscode.window.terminals`, finds the match, calls `terminal.show()`
This would replace the AppleScript navigation entirely for Cursor sessions.
