#!/usr/bin/env bash
# Shared navigation functions for claude-next-idle and claude-next-fresh.
# Source this file — do not execute directly.
#
# Requires: log() function defined before sourcing.

# Detect which app hosts the session: "iterm", "cursor", or "unknown"
detect_session_app() {
    local cwd="$1"
    local project_name
    project_name=$(basename "$cwd")

    local iterm_match
    iterm_match=$(osascript - "$project_name" <<'AS' 2>/dev/null || true
on run argv
    set pn to item 1 of argv
    tell application "System Events"
        if not (exists process "iTerm2") then return "no"
    end tell
    tell application "iTerm"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if name of s contains pn then return "yes"
                end repeat
            end repeat
        end repeat
    end tell
    return "no"
end run
AS
)
    if [ "$iterm_match" = "yes" ]; then
        echo "iterm"
        return
    fi

    local cursor_match
    cursor_match=$(osascript - "$project_name" <<'AS' 2>/dev/null || true
on run argv
    set pn to item 1 of argv
    tell application "System Events"
        if not (exists process "Cursor") then return "no"
        tell process "Cursor"
            repeat with w in windows
                if name of w contains pn then return "yes"
            end repeat
        end tell
    end tell
    return "no"
end run
AS
)
    if [ "$cursor_match" = "yes" ]; then
        echo "cursor"
        return
    fi

    echo "unknown"
}

activate_cursor_window() {
    local project_name="$1"
    log "activating Cursor window for: $project_name"

    osascript - "$project_name" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set projectName to item 1 of argv
    tell application "System Events"
        tell process "Cursor"
            set frontmost to true
            repeat with w in windows
                if name of w contains projectName then
                    perform action "AXRaise" of w
                    return "found"
                end if
            end repeat
            return "not_found"
        end tell
    end tell
end run
APPLESCRIPT
}

activate_iterm_by_tty() {
    local tty_dev="$1"
    log "activating iTerm session by TTY: $tty_dev"

    osascript - "$tty_dev" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set ttyDev to item 1 of argv
    tell application "iTerm"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if tty of s is ttyDev then
                        set index of w to 1
                        select t
                        select s
                        return "found"
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    return "not_found"
end run
APPLESCRIPT
}

navigate_to_session() {
    local cwd="$1"
    local pid="$2"
    local project_name
    project_name=$(basename "$cwd")

    # Try iTerm by TTY first (most reliable — matches exact terminal session)
    if [ -n "$pid" ]; then
        local tty
        tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
        if [ -n "$tty" ] && [ "$tty" != "??" ]; then
            log "found TTY $tty for PID $pid (project: $project_name)"
            local result
            result=$(activate_iterm_by_tty "/dev/$tty")
            if [ "$result" = "found" ]; then
                echo "found"
                return
            fi
        fi
    fi

    # Fallback: detect by project name in window/session titles
    local app
    app=$(detect_session_app "$cwd")
    log "detected app: $app for project: $project_name"

    case "$app" in
        cursor)
            activate_cursor_window "$project_name"
            ;;
        iterm)
            osascript - "$project_name" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set projectName to item 1 of argv
    tell application "iTerm"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if name of s contains projectName then
                        set index of w to 1
                        select t
                        return "found"
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    return "not_found"
end run
APPLESCRIPT
            ;;
        *)
            log "no matching window found in Cursor or iTerm"
            echo "not_found"
            ;;
    esac
}
