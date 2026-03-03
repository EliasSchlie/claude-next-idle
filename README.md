# claude-next-idle

LIFO stack for cycling through idle Claude Code sessions. Jump to the next session waiting for your review.

## How it works

When you run multiple Claude Code sessions in parallel, `claude-next-idle` tracks which ones are idle (waiting for input) and which are processing. Press a keyboard shortcut to jump to the most recently finished session. Press again for the next one.

```
Session finishes → enters TOP of stack
You visit it     → moves to BOTTOM of stack
You type in it   → leaves the stack (now processing)
```

## Install

```bash
# Copy to PATH
cp bin/claude-next-idle ~/.local/bin/
chmod +x ~/.local/bin/claude-next-idle
```

Then set up a [Keyboard Maestro](https://www.keyboardmaestro.com/) macro that runs:
```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
claude-next-idle --debug 2>&1
```
And shows the result as a notification.

## Usage

```bash
claude-next-idle              # Jump to next idle session
claude-next-idle --list       # Show idle stack + processing sessions
claude-next-idle --count      # Print "idle/processing" counts (e.g. "3/1")
claude-next-idle --reset      # Clear stack ordering
claude-next-idle --debug      # Jump with verbose logging to ~/claude-next-idle.log
```

## Requirements

- macOS (uses AppleScript, `stat -f`, `pgrep`, `lsof`)
- Bash 3.2+ (ships with macOS)
- Python 3 (for JSONL parsing)
- Claude Code (reads `~/.claude/projects/**/*.jsonl`)

## Sub-claude exclusion

Sessions spawned by [sub-claude](https://github.com/EliasSchlie/sub-claude) are automatically excluded via:
- `SUB_CLAUDE=1` environment variable on running processes
- Session IDs from `~/.sub-claude/pools/*/jobs/*/meta.json`
- Temp directory patterns in JSONL paths

## Limitations

- **Raises the correct Cursor/iTerm window** but cannot switch to a specific terminal tab within Cursor (would need a VS Code extension)
- macOS only
