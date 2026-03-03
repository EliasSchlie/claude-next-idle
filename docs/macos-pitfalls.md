# macOS CLI Pitfalls

Hard-learned rules from building process-inspection tools on macOS.

## pgrep Is Unreliable

`pgrep -x claude` silently misses processes. Verified: with 13 `claude` processes running, `pgrep` returned only 12. The miss is consistent and reproducible.

**Use `ps -eo pid=,comm=` instead:**

```bash
# Bad — misses processes
PIDS=$(pgrep -x claude)

# Good — reliable
PIDS=$(ps -eo pid=,comm= | awk '$2 == "claude" {print $1}')
```

No known workaround for `pgrep`. The root cause is unknown (not a permissions issue, not a timing issue).

## PWD Extraction from `ps eww`

`ps eww` output shows environment variables as space-separated `KEY=value` pairs. Extracting `PWD` has a subtle trap:

```bash
# Bad — matches OLDPWD too!
# "OLDPWD=/Users/mee" contains substring "PWD=/Users/mee"
pwd=$(echo "$line" | grep -o 'PWD=[^ ]*' | head -1 | cut -d= -f2)

# Good — requires space before PWD, excluding OLDPWD
pwd=$(echo "$line" | grep -oE '[[:space:]]PWD=[^[:space:]]+' | head -1 | sed 's/^[[:space:]]*PWD=//')
```

The space-before-PWD pattern works because `OLDPWD` is preceded by a space before the `O`, not before the `P`. So `[[:space:]]PWD=` matches ` PWD=value` but not ` OLDPWD=value`.

### PWD vs Project Directory

PWD may not match the JSONL project directory. Claude Code can determine the project independently of the launch CWD (e.g., session resume). The shell might be in `/Users/mee` while Claude's project is `/Users/mee/Documents/Projects/foo`.

### Paths With Spaces

`ps eww` env vars are space-separated with no escaping. A PWD like `/Users/mee/My Projects/foo` would be truncated to `/Users/mee/My`. No reliable fix using `ps eww` alone — use `lsof -a -d cwd` on the parent shell PID as an alternative.

## lsof Gotchas

### The `-a` Flag Is Mandatory for Combined Filters

Without `-a`, `lsof` uses OR logic when combining flags:

```bash
# Bad — returns ALL processes with that fd type AND the specified PID's files
lsof -d cwd -p $PID

# Good — AND logic, returns only the specified PID's cwd
lsof -a -d cwd -p $PID
```

### Claude Process CWD

Claude Code's Node.js process always has CWD `/`. Use the parent shell's CWD or the `PWD` env var instead.

### JSONL Files Are Not Kept Open

Claude opens and closes JSONL files per write. `lsof | grep .jsonl` will not reliably show which process owns which file. The `.claude/tasks/` directory approach works for some processes but not all.

### Batch lsof Calls

For multiple PIDs, batch into a single call:

```bash
# Bad — N lsof calls
for pid in $PIDS; do lsof -p "$pid"; done

# Good — 1 lsof call
lsof -p "$(echo $PIDS | tr ' ' ',')"
```

## Bash 3.2 Compatibility

macOS ships bash 3.2. Key limitations:

| Feature | Bash 3.2 | Workaround |
|---------|----------|------------|
| Associative arrays | `local -A` fails | `grep -F` with temp files |
| `trap ... RETURN` | Silently ignored, leaks temp files | Explicit `rm -f` at every exit point |
| `${var:offset:length}` | Works | (no issue) |
| `[[ ]]` with glob patterns | Works | (no issue) |
| `$'\n'` | Works | (no issue) |
