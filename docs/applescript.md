# AppleScript & Electron Apps

Rules for automating macOS apps via AppleScript, especially Electron-based editors (Cursor, VS Code).

## NEVER Send Synthetic Keystrokes to Electron Apps

AppleScript `keystroke` commands to Cursor/VS Code are fundamentally broken:

- Keystrokes arrive at whatever window has focus, which may change during execution
- Command palette automation (`Cmd+Shift+P` → type command → Enter) fails catastrophically — activates random features, resizes windows, triggers system shortcuts
- Timing-dependent: delay between keystrokes is unreliable

**Safe operations** (use Accessibility API, not keyboard simulation):
- `AXRaise` — raise a specific window
- `set frontmost` — activate the app
- Reading window properties (title, position, size)

**Unsafe operations** (use keyboard simulation):
- `keystroke` / `key code`
- Any sequence that types into a UI element

### Terminal Tab Navigation in Cursor

The only reliable way to switch terminal tabs is a VS Code extension that:
1. Listens for a command (e.g., `claude-next-idle.focusTerminal`)
2. Accepts a session ID or project name
3. Iterates `vscode.window.terminals`, finds the match, calls `terminal.show()`

The Accessibility tree for Electron is too opaque for tab-level navigation.

## iTerm AppleScript

iTerm2 (addressed as `"iTerm"` in AppleScript) has a proper scripting dictionary:

### Window/Tab/Session Navigation

```applescript
tell application "iTerm"
    -- Bring window to front
    set index of w to 1
    -- Select a tab
    select t
    -- Select a session within a tab
    select s
end tell
```

### Finding a Session by TTY

```applescript
tell application "iTerm"
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                if tty of s is "/dev/ttys014" then
                    set index of w to 1
                    select t
                    select s
                    return "found"
                end if
            end repeat
        end repeat
    end repeat
end tell
```

### Session Properties

| Property | Description |
|----------|-------------|
| `tty` | Terminal device path (e.g., `/dev/ttys014`) |
| `name` | Terminal title (shows running command or CWD) |

### Session Name Limitations

The `name` property shows the terminal title, which for Claude sessions typically shows `✳ Claude Code (claude)` — it does NOT include the project name. This makes name-based matching unreliable for distinguishing between multiple Claude sessions. Use TTY-based matching instead.

## Cursor/VS Code Window Matching

For raising the correct Cursor window (without keystroke simulation):

```applescript
tell application "System Events"
    tell process "Cursor"
        set frontmost to true
        repeat with w in windows
            if name of w contains projectName then
                perform action "AXRaise" of w
                return "found"
            end if
        end repeat
    end tell
end tell
```

This uses the Accessibility API (`AXRaise`) which is safe and reliable. Window `name` contains the project/file name shown in the title bar.
