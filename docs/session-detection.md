# Session Detection

How `claude-next-idle` detects idle sessions using Claude Code hooks.

## Hook-Based Detection

Idle state is tracked via **signal files** written by hooks, not by parsing JSONL transcripts.

### Signal Files

Location: `~/.claude/idle-signals/<claude-pid>`

Format: `{"cwd":"...","session_id":"...","transcript":"...","ts":...,"trigger":"..."}`

- **Written** when a session becomes idle (waiting for user input)
- **Cleared** when a session starts processing again
- **Stale signals** (dead PIDs) are cleaned up by `bin/claude-next-idle` on each run

### Hooks

| Event | Action | Trigger |
|-------|--------|---------|
| `Stop` | Write signal | Claude finished responding |
| `PreToolUse` (AskUserQuestion\|ExitPlanMode) | Write signal | Claude asking user a question or presenting a plan |
| `PermissionRequest` | Write signal | Claude requesting tool permission |
| `PostToolUse` | Clear signal | Claude continuing to process |
| `UserPromptSubmit` | Clear signal | User sent a new message |
| `SessionStart` (clear) | Clear signal | User ran `/clear` |

All hooks are async. The hook script uses `$PPID` (set to the Claude process that spawned the hook).

Note: `/clear` does NOT trigger `UserPromptSubmit` — it triggers `SessionStart` with source `clear`.

### Block Detection

When a `Stop` hook fires, the session might not actually be idle — another hook (e.g., a lint hook) may have blocked the response, causing Claude to continue. Detection:

1. Write signal file immediately
2. Record the JSONL transcript's mtime
3. Sleep 1 second
4. If the signal was already cleared (by PostToolUse/UserPromptSubmit), stop
5. Compare transcript mtime — if it increased, the session continued → remove signal

### Sub-Claude Exclusion

`SUB_CLAUDE=1` env var is checked at the top of `idle-signal.sh`. Sub-claude processes never write signals.

## Processing Session Detection

Processing sessions are found at query time by `bin/claude-next-idle`:

1. Find all alive `claude` PIDs via `ps -eo pid=,comm=`
2. Exclude PIDs with `SUB_CLAUDE=1` in their environment (`ps eww`)
3. Exclude PIDs that have signal files (idle)
4. Remaining PIDs = processing sessions
5. CWD extracted from `PWD=` in the process environment

## Navigation

Each idle session has a PID from the signal file name. Navigation:

1. `ps -o tty= -p PID` → get terminal device (e.g., `ttys014`)
2. iTerm AppleScript matches by `tty of s` → selects window/tab/session
3. Fallback: project-name matching in iTerm session names or Cursor window titles

See [applescript.md](applescript.md) for iTerm/Cursor navigation details.
