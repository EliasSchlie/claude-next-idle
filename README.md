# claude-next-idle

**Jump to the next Claude Code session that needs your attention.**

When you run multiple Claude Code sessions in parallel, keeping track of which ones are waiting for you becomes impossible. `claude-next-idle` solves this with a LIFO stack - press a keyboard shortcut to instantly jump to the most recently finished session. Press again for the next one.

It also includes `claude-next-fresh` for jumping to empty sessions ready for new work.

## How It Works

```
Session finishes → enters TOP of stack
You visit it     → moves to BOTTOM of stack
You type in it   → leaves the stack (now active)
```

Idle detection is powered by [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) - no JSONL parsing, no polling. Hooks fire on lifecycle events (Stop, PreToolUse, PermissionRequest, PostToolUse, UserPromptSubmit, SessionStart) and write/clear lightweight signal files.

## Install

### Plugin (hooks)

```bash
claude plugin install claude-next-idle@elias-tools
```

This installs the hooks that track session state. The plugin auto-updates when new versions are published.

### CLI tools

```bash
git clone https://github.com/EliasSchlie/claude-next-idle.git
cd claude-next-idle
./install.sh    # symlinks bin/* → ~/.local/bin/
```

### Keyboard shortcut

Set up a [Keyboard Maestro](https://www.keyboardmaestro.com/) macro (or any hotkey tool) that runs:

```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
claude-next-idle --debug 2>&1
```

Show the result as a notification so you get feedback ("Jumped to project-name" / "No idle sessions").

**Tip:** `--count` is handy for a status bar widget — it prints `idle/active` (e.g. `3/1`) with no side effects.

## Usage

```bash
claude-next-idle              # Jump to next idle session
claude-next-idle --list       # Show idle stack + active sessions
claude-next-idle --count      # Print "idle/active" counts (e.g. "3/1")
claude-next-idle --reset      # Clear stack ordering
claude-next-idle --debug      # Jump with verbose logging

claude-next-fresh             # Jump to next fresh/empty session
claude-next-fresh --list      # Show fresh sessions
claude-next-fresh --count     # Print fresh session count
```

## Architecture

```
hooks/
  idle-signal.sh    - hook script: writes/clears signal files on session events
  hooks.json        - Claude Code hook configuration

bin/
  claude-next-idle  - reads idle signals, maintains LIFO stack, navigates
  claude-next-fresh - reads fresh signals, maintains LIFO stack, navigates

lib/
  navigate.sh       - shared AppleScript navigation (iTerm TTY, Cursor window)
  stack.sh          - shared LIFO stack logic
```

**Signal files** live at `~/.claude/idle-signals/<pid>` and `~/.claude/fresh-signals/<pid>`. They contain JSON with the session's CWD, session ID, and timestamp.

**Navigation** resolves PID → TTY → iTerm session (via AppleScript). Falls back to project-name matching in Cursor window titles.

## Key Design Decisions

- **Hook-based detection** - no JSONL parsing or polling. Hooks fire on lifecycle events and write signal files instantly.
- **Block detection** - Stop hook waits 1s and checks if the transcript was modified by another hook. Prevents false idle signals when lint hooks block responses.
- **Sub-claude exclusion** - sessions with `SUB_CLAUDE=1` env var never write signals, so automated sub-agent sessions don't pollute the stack.
- **Cleared-session exclusion** - `/clear` triggers `SessionStart`, not `UserPromptSubmit`. A dedicated hook clears idle signals for cleared sessions.

## Requirements

- macOS (uses AppleScript for terminal navigation)
- Bash 3.2+ (ships with macOS)
- Python 3 (for JSON parsing in hooks)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with hooks support
- iTerm2 or Cursor (for terminal navigation)

## Known Limitations

- **Cursor**: raises the correct window but cannot switch to a specific terminal tab (would need a VS Code extension)
- **Block detection latency**: 1s verification window means a session briefly appears idle before block detection completes

## License

[MIT](LICENSE) - Elias Schlie
