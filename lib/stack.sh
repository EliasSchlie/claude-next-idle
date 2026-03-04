#!/usr/bin/env bash
# Shared stack engine for claude-next-idle and claude-next-fresh.
# Source this file — do not execute directly.
#
# Required variables before sourcing:
#   STACK_FILE  — path to the stack file
#   LOCK_DIR    — path to the lock directory
#   SIGNAL_DIR  — path to the signal directory
#   LOG_FILE    — path to the debug log file
#   DEBUG       — 0 or 1

# --- logging ---

log() {
    [ "$DEBUG" -eq 0 ] && return
    echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"
}

# --- locking (mkdir-based, works on macOS bash 3.2) ---

acquire_lock() {
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        local lock_age
        lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
        if [ "$lock_age" -gt 30 ]; then
            rm -rf "$LOCK_DIR" && mkdir "$LOCK_DIR" 2>/dev/null || exit 0
        else
            log "BLOCKED: another instance holds the lock (age=${lock_age}s)"
            exit 0
        fi
    fi
    trap 'rm -rf "$LOCK_DIR"' EXIT
}

# --- session detection ---

# Read sessions from signal files in SIGNAL_DIR.
# Output: pid|cwd|ts per session. Cleans up stale signals (dead PIDs).
get_sessions() {
    mkdir -p "$SIGNAL_DIR"
    for signal_file in "$SIGNAL_DIR"/*; do
        [ -f "$signal_file" ] || continue
        local pid cwd ts
        pid=$(basename "$signal_file")

        # Verify PID is still alive and is a claude process
        if ! ps -o comm= -p "$pid" 2>/dev/null | grep -qx "claude"; then
            log "cleaning stale signal: PID=$pid (dead)"
            rm -f "$signal_file"
            continue
        fi

        # Parse signal metadata
        local parsed
        parsed=$(jq -r '[.cwd // "", .ts // 0] | join("|")' < "$signal_file" 2>/dev/null) || true
        cwd="${parsed%|*}"
        ts="${parsed##*|}"

        [ -z "$cwd" ] && continue
        log "signal: PID=$pid CWD=$cwd TS=$ts"
        echo "${pid}|${cwd}|${ts}"
    done
}

# --- stack management ---

# Stack file format: pid|cwd|ts
rebuild_stack() {
    local sessions="$1"
    local tmp_sessions tmp_stack_pids tmp_new
    tmp_sessions=$(mktemp)
    tmp_stack_pids=$(mktemp)
    tmp_new=$(mktemp)

    echo "$sessions" | grep -v '^$' > "$tmp_sessions" || true
    log "sessions found: $(wc -l < "$tmp_sessions" | tr -d ' ')"

    # Preserve ordering of sessions already in the stack (keyed by PID)
    local kept_lines=""
    if [ -f "$STACK_FILE" ]; then
        while IFS='|' read -r pid _rest; do
            [ -z "$pid" ] && continue
            if grep -q "^${pid}|" "$tmp_sessions" 2>/dev/null; then
                local fresh_data
                fresh_data=$(grep "^${pid}|" "$tmp_sessions" | head -1)
                kept_lines="${kept_lines}${fresh_data}"$'\n'
                echo "$pid" >> "$tmp_stack_pids"
            fi
        done < "$STACK_FILE"
    fi

    # New sessions not yet in the stack
    while IFS='|' read -r pid cwd ts; do
        [ -z "$pid" ] && continue
        if ! grep -qxF "$pid" "$tmp_stack_pids" 2>/dev/null; then
            echo "${ts}|${pid}|${cwd}|${ts}" >> "$tmp_new"
        fi
    done < "$tmp_sessions"

    # Stack = new sessions (sorted by ts desc, at top) + existing sessions (preserved order)
    {
        sort -t'|' -k1 -rn "$tmp_new" 2>/dev/null | while IFS='|' read -r _sort_ts pid cwd ts; do
            [ -z "$pid" ] && continue
            echo "${pid}|${cwd}|${ts}"
        done
        printf '%s' "$kept_lines"
    } | grep -v '^$' > "$STACK_FILE" || true

    rm -f "$tmp_sessions" "$tmp_stack_pids" "$tmp_new"
    log "stack rebuilt: $(wc -l < "$STACK_FILE" | tr -d ' ') entries"
}

rotate_to_bottom() {
    local target="$1"
    local tmp
    tmp=$(mktemp)
    grep -v "^${target}|" "$STACK_FILE" > "$tmp" 2>/dev/null || true
    grep "^${target}|" "$STACK_FILE" >> "$tmp" 2>/dev/null || true
    mv "$tmp" "$STACK_FILE"
}

# --- display helpers ---

# Print the stack as a numbered list. Disambiguates duplicate project names with PID.
print_stack_list() {
    local pos=1
    if [ -f "$STACK_FILE" ]; then
        local dup_names
        dup_names=$(while IFS='|' read -r _pid cwd _ts; do
            basename "$cwd" 2>/dev/null
        done < "$STACK_FILE" | sort | uniq -d)

        while IFS='|' read -r pid cwd _ts; do
            [ -z "$pid" ] && continue
            local project
            project=$(basename "$cwd")
            if echo "$dup_names" | grep -qxF "$project" 2>/dev/null; then
                printf "  %2d. %s (PID %s)\n" "$pos" "$project" "$pid"
            else
                printf "  %2d. %s\n" "$pos" "$project"
            fi
            pos=$((pos + 1))
        done < "$STACK_FILE"
    fi
    if [ "$((pos - 1))" -eq 0 ]; then
        echo "  (none)"
    fi
}

# Jump to the top of the stack, rotate it to bottom, navigate.
# Args: $1 = suffix for output (e.g. ", 3 processing" or " fresh")
jump_to_top() {
    local suffix="${1:-}"
    local top
    top=$(head -1 "$STACK_FILE" 2>/dev/null || true)
    if [ -z "$top" ]; then
        return 1
    fi

    local pid cwd _ts
    IFS='|' read -r pid cwd _ts <<< "$top"
    local project
    project=$(basename "$cwd")
    log "jumping to: $project (PID=$pid)"

    rotate_to_bottom "$pid"

    local result remaining
    result=$(navigate_to_session "$cwd" "$pid")
    remaining=$(grep -c '|' "$STACK_FILE" 2>/dev/null) || remaining=0
    remaining=$((remaining - 1))

    if [ "$result" = "found" ]; then
        echo "→ $project  ($remaining more${suffix})"
    else
        log "FAILED: window not found for $project"
        echo "→ $project  [not found]  ($remaining more${suffix})"
    fi
}

# --- flag parsing ---

parse_flags() {
    export MODE=""
    for arg in "$@"; do
        case "$arg" in
            --debug) DEBUG=1 ;;
            --list|--count|--reset) MODE="$arg" ;;
        esac
    done
}

init_debug() {
    local name="$1"
    if [ "$DEBUG" -eq 1 ]; then
        echo "=== $name debug $(date) ===" >> "$LOG_FILE"
        log "PATH=$PATH"
        log "jq=$(which jq 2>/dev/null || echo MISSING)"
        log "osascript=$(which osascript 2>/dev/null || echo MISSING)"
    fi
}
