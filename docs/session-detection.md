# Session Detection & Process Matching

How `claude-next-idle` discovers, classifies, and matches Claude Code sessions to live processes.

## JSONL-Based Session Discovery

Sessions are detected from `~/.claude/projects/**/*.jsonl` files modified within the last 120 minutes.

### JSONL Structure

Each line is a JSON object with a `type` field. Key types:

| Type | Meaning |
|------|---------|
| `user` | User message (or system-generated pseudo-user message) |
| `assistant` | Claude's response |
| `system` | System message (noise) |
| `progress` | Streaming progress (noise) |
| `file-history-snapshot` | File tracking (noise) |
| `pr-link` | PR link (noise) |

Noise types get appended AFTER the assistant finishes responding, so they must be skipped when determining the last meaningful message type.

### Status Classification

The last meaningful message type + real-user presence determines status:

- `assistant` + has real user → **idle** (Claude responded, waiting for user)
- `assistant` + no real user → **fresh** (new or cleared session, excluded from stack)
- `user` + has real user → **processing** (user sent message, Claude working)
- `user` + no real user → **fresh** (e.g., right after `/clear` before first real message)

### CWD Extraction

The `cwd` field appears in early JSONL entries (first 30 lines). It tracks Claude's current working directory and updates when Claude `cd`s.

### Fresh Session Detection

A session is "fresh" if it has no real user messages. System-generated `type=user` entries have content starting with `<` (e.g., `<local-command-caveat>`, `<command-name>`). These are filtered out — only entries with content NOT starting with `<` (or content that is a list) count as real user messages.

Fresh sessions are excluded from the idle rotation stack.

### `/clear` Handling

`/clear` creates a **new JSONL** file. The old file retains all messages but loses its live process (same PID now writes to the new file). The new file starts with only system-generated `type=user` entries (`<command-name>/clear</command-name>`, etc.), so `has_real_user` is false → status is **fresh** until the user sends their first real message.

## Process Matching

Each JSONL must be matched to a specific live claude process to confirm the session is alive. Two methods, tried in order:

### 1. Session ID Match (Precise)

`lsof -p PID | grep .claude/tasks/` → the directory basename is the session UUID.

- Gives exact PID → session ID mapping
- **NOT all processes have tasks/ open** — only those with active task tracking
- Cannot use `lsof | grep .jsonl` — files are opened/closed per write, not kept open

### 2. CWD Pool Match (Heuristic)

When session ID matching fails, fall back to CWD-based pool matching:

1. Group processes by `PWD` env var
2. Group JSONLs by `cwd` field
3. For each CWD, the N most recent JSONLs (by mtime) claim the N available processes
4. Excess JSONLs = dead sessions, excluded

This handles **multiple sessions in the same directory**: if 3 processes have PWD=/path/to/project and 5 JSONLs have cwd=/path/to/project, the 3 most recently modified JSONLs are considered alive.

### Process Discovery

All non-sub-claude `claude` processes are found via `ps -eo pid=,comm=`. See [macOS pitfalls](macos-pitfalls.md#pgrep-is-unreliable) for why `pgrep` is not used.

## Sub-Claude Exclusion

Three layers filter out sub-claude worker processes:

1. **Environment variable**: `ps eww -p PID | grep SUB_CLAUDE=1` on running processes
2. **Job metadata**: `~/.sub-claude/pools/*/jobs/*/meta.json` → `claude_session_id` field
3. **Path pattern**: JSONL project dirs containing `-tmp-` or `tmp.` (worktree sessions)

Layers 1+2 catch sub-claude agents in real project dirs; layer 3 catches worktree-based agents.

## Pre-Filtering

Before classification, these sessions are excluded:
- `agent-*` session IDs (subagent sessions)
- Sessions in project dirs matching sub-claude path patterns
- Sessions whose ID appears in the sub-claude exclusion set

## Navigation

After matching, each session has a PID. Navigation uses PID → TTY → iTerm AppleScript:

1. `ps -o tty= -p PID` → get the terminal device (e.g., `ttys014`)
2. iTerm AppleScript iterates all sessions, matches by `tty of s`
3. Brings that window to front and selects the tab/session

Fallback: project-name matching in iTerm session titles or Cursor window titles.

### Same-CWD Navigation Imprecision

When multiple sessions share a CWD, the PID-to-JSONL pairing within that CWD is heuristic (by mtime). Navigation may land on the wrong terminal of the same project. Cycling through the stack visits all sessions eventually.
