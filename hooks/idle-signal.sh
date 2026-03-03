#!/usr/bin/env bash
# Signals when a Claude session becomes idle or starts processing.
# Called by Claude Code hooks (Stop, PreToolUse, PermissionRequest,
# PostToolUse, UserPromptSubmit).
#
# Usage: idle-signal.sh write [stop|tool|permission]
#        idle-signal.sh clear
#
# Signal files: ~/.claude/idle-signals/<claude-pid>
# Format: {"cwd":"...","session_id":"...","transcript":"...","ts":...}

set -euo pipefail

# Skip sub-claude sessions
[ "${SUB_CLAUDE:-}" = "1" ] && exit 0

SIGNAL_DIR="$HOME/.claude/idle-signals"
mkdir -p "$SIGNAL_DIR"

# $PPID is the Claude process that spawned this hook
claude_pid="$PPID"
signal_file="$SIGNAL_DIR/$claude_pid"

# Read hook input from stdin (JSON with session_id, transcript_path, etc.)
# Note: async hooks receive JSON without a trailing newline, causing `read`
# to return exit code 1 despite capturing the data. Use `|| true` to handle this.
read_input() {
    local line=""
    read -t 1 -r line 2>/dev/null || true
    if [ -n "$line" ]; then
        echo "$line"
        cat 2>/dev/null
    fi
}

case "${1:-}" in
    write)
        trigger="${2:-unknown}"
        input=$(read_input)
        session_id=""
        transcript=""
        if [ -n "$input" ]; then
            session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null) || true
            transcript=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null) || true
        fi

        jq -n --arg cwd "$(pwd)" --arg sid "$session_id" --arg tr "$transcript" \
            --argjson ts "$(date +%s)" --arg trig "$trigger" \
            '{cwd:$cwd,session_id:$sid,transcript:$tr,ts:$ts,trigger:$trig}' > "$signal_file"

        # Block detection (Stop only): wait, then verify the session didn't continue.
        # Another Stop hook may have blocked → Claude gets re-prompted → not idle.
        if [ "$trigger" = "stop" ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
            saved_mtime=$(stat -f %m "$transcript" 2>/dev/null || echo 0)
            sleep 1
            # If signal was already cleared by UserPromptSubmit/PostToolUse, stop
            [ -f "$signal_file" ] || exit 0
            current_mtime=$(stat -f %m "$transcript" 2>/dev/null || echo 0)
            if [ "$current_mtime" -gt "$saved_mtime" ]; then
                # JSONL was modified after signal → session continued → not idle
                rm -f "$signal_file"
            fi
        fi
        ;;
    clear)
        rm -f "$signal_file"
        ;;
esac
