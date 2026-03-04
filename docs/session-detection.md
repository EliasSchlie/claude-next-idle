# Session Detection

How `claude-next-idle` and `claude-next-fresh` detect session states using Claude Code hooks.

## Hook-Based Detection

Idle state is tracked via **signal files** written by hooks, not by parsing JSONL transcripts.

### Signal Files

Location: `~/.claude/idle-signals/<claude-pid>`

Format: `{"cwd":"...","session_id":"...","transcript":"...","ts":...,"trigger":"..."}`

- **Written** when a session becomes idle (waiting for user input)
- **Cleared** when a session starts processing again
- **Stale signals** (dead PIDs) are cleaned up by `bin/claude-next-idle` on each run

### Hooks

| Event | Idle signal | Fresh signal | Trigger |
|-------|-------------|--------------|---------|
| `Stop` | Write | — | Claude finished responding |
| `PreToolUse` (AskUserQuestion\|ExitPlanMode) | Write | — | Claude asking user a question or presenting a plan |
| `PermissionRequest` | Write | — | Claude requesting tool permission |
| `PostToolUse` | Clear | — | Claude continuing to process |
| `UserPromptSubmit` | Clear | Clear | User sent a new message |
| `SessionStart` (clear) | Clear | — | User ran `/clear` |
| `SessionStart` (any) | — | Write | Session started or cleared |

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

## Fresh Session Detection

Fresh sessions are those at an empty prompt — just started or just `/clear`'d.

### Signal Files

Location: `~/.claude/fresh-signals/<claude-pid>`

Format: `{"cwd":"...","ts":...}`

- **Written** on every `SessionStart` (new session or `/clear`)
- **Cleared** on `UserPromptSubmit` (user typed something)
- **Stale signals** (dead PIDs) are cleaned up by `bin/claude-next-fresh` on each run

### Lifecycle

1. User starts Claude → `SessionStart` fires → fresh signal written
2. User types a message → `UserPromptSubmit` fires → fresh signal cleared
3. User runs `/clear` → `SessionStart` (clear) fires → fresh signal written again

## Processing Session Detection

Processing sessions are found at query time by `bin/claude-next-idle`:

1. Find all alive `claude` PIDs via `ps -eo pid=,comm=`
2. Exclude PIDs with `SUB_CLAUDE=1` in their environment (`ps eww`)
3. Exclude PIDs that have signal files (idle)
4. Remaining PIDs = processing sessions
5. CWD extracted from `PWD=` in the process environment

## Navigation

Both idle and fresh sessions have a PID from the signal file name. Navigation logic is shared in `lib/navigate.sh`:

1. `ps -o tty= -p PID` → get terminal device (e.g., `ttys014`)
2. iTerm AppleScript matches by `tty of s` → selects window/tab/session
3. Fallback: project-name matching in iTerm session names or Cursor window titles

See [applescript.md](applescript.md) for iTerm/Cursor navigation details.
