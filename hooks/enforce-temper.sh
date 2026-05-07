#!/usr/bin/env bash
# enforce-temper.sh — PreToolUse command hook (matcher: Bash)
#
# Blocks high-risk git operations and nudges the agent to run /temper first.
# This is Tier 2 (reactive). The proactive Tier 1 rules live in templates/CLAUDE.md.
#
# Triggers:
#   git push *        — always (except --dry-run)
#   git commit *      — if staged diff exceeds size threshold or touches critical paths
#   git merge *       — if merging into a primary branch (main/master/develop/trunk)
#   git rebase -i *   — if rebase range exceeds 5 commits
#   git stash pop *   — if stash diff exceeds size threshold
#
# Bypass: append  # temper:skip  (or  # suite:skip  to silence all suite hooks) to any command.
# Exit 1 = block the command and show the message.
# Exit 0 = allow silently.

set -euo pipefail

GLOBAL_CONFIG="$HOME/.claude/temper.config"
LOCAL_CONFIG="./temper.config"

input=$(cat)

cmd=$(printf '%s' "$input" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('command', ''))
" 2>/dev/null) || exit 0

[ -z "$cmd" ] && exit 0

# Bypass marker — accepts # temper:skip or # suite:skip (silences all suite hooks)
if printf '%s' "$cmd" | grep -qE '# *(temper|suite):skip'; then
  exit 0
fi

# Check enabled state from config
_config_get() {
  local key="$1"
  local val=""
  [ -f "$GLOBAL_CONFIG" ] && val=$(grep "^$key:" "$GLOBAL_CONFIG" | sed "s/^$key: *//" | head -1) || true
  [ -f "$LOCAL_CONFIG"  ] && { local lv; lv=$(grep "^$key:" "$LOCAL_CONFIG" | sed "s/^$key: *//" | head -1 2>/dev/null) && [ -n "$lv" ] && val="$lv"; } || true
  printf '%s' "$val"
}

enabled=$(_config_get "enabled")
[ "$enabled" = "false" ] && exit 0

auto_nudge_lines=$(_config_get "auto_nudge_lines")
auto_nudge_lines=${auto_nudge_lines:-200}
auto_nudge_files=$(_config_get "auto_nudge_files")
auto_nudge_files=${auto_nudge_files:-10}
critical_paths=$(_config_get "critical_paths")
critical_paths=${critical_paths:-"*auth*|*permission*|*token*|migrations/|*alembic*|\\.sql|*schema*|*secret*|*credential*|\\.env"}

# Write the main logic to a temp file to avoid heredoc/quoting issues
_tmppy=$(mktemp /tmp/temper_check.XXXXXX.py)
cat > "$_tmppy" << 'PYEOF'
import re, subprocess, sys, os

cmd = sys.argv[1]
auto_nudge_lines = int(sys.argv[2])
auto_nudge_files = int(sys.argv[3])
critical_paths_raw = sys.argv[4]

def run(args):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=10)
        return r.stdout.strip()
    except Exception:
        return ""

# ── git push ─────────────────────────────────────────────────────────────────
if re.match(r'\bgit\b\s+push\b', cmd):
    # Allow dry-run passes through
    if re.search(r'--dry-run|-n\b', cmd):
        print("none")
        sys.exit(0)
    print("push")
    sys.exit(0)

# ── git commit ────────────────────────────────────────────────────────────────
if re.match(r'\bgit\b\s+commit\b', cmd):
    # Count staged diff stats
    shortstat = run(["git", "diff", "--staged", "--shortstat"])
    lines = sum(int(x) for x in re.findall(r'(\d+) (?:insertion|deletion)', shortstat))
    files_out = run(["git", "diff", "--staged", "--name-only"])
    files = len([f for f in files_out.splitlines() if f]) if files_out else 0

    if lines > auto_nudge_lines or files > auto_nudge_files:
        print("commit_large")
        sys.exit(0)

    # Critical path check — patterns are pipe-separated extended regex
    patterns = [p.strip().replace("*", ".*") for p in critical_paths_raw.split("|")]
    staged_files = files_out.splitlines() if files_out else []
    for filepath in staged_files:
        for pat in patterns:
            if re.search(pat, filepath, re.IGNORECASE):
                print("commit_critical")
                sys.exit(0)

    print("none")
    sys.exit(0)

# ── git merge ─────────────────────────────────────────────────────────────────
if re.match(r'\bgit\b\s+merge\b', cmd):
    primary = {"main", "master", "develop", "trunk"}
    # Extract branch name from command (last non-flag token)
    tokens = [t for t in cmd.split() if not t.startswith("-")]
    branch = tokens[-1] if len(tokens) > 2 else ""
    if branch in primary:
        print("merge_primary")
    else:
        print("none")
    sys.exit(0)

# ── git rebase -i ─────────────────────────────────────────────────────────────
if re.match(r'\bgit\b\s+rebase\b.*-i\b', cmd) or re.match(r'\bgit\b\s+rebase\b\s+-i\b', cmd):
    tokens = cmd.split()
    # Find the ref argument (last non-flag token after "rebase")
    rebase_idx = next((i for i, t in enumerate(tokens) if t == "rebase"), -1)
    ref = None
    for t in tokens[rebase_idx + 1:]:
        if not t.startswith("-"):
            ref = t
            break

    if ref is None:
        print("none")
        sys.exit(0)

    # Try to parse HEAD~N directly
    m = re.match(r'HEAD~(\d+)', ref, re.IGNORECASE)
    if m:
        count = int(m.group(1))
    else:
        out = run(["git", "rev-list", "--count", f"HEAD...{ref}"])
        try:
            count = int(out)
        except ValueError:
            count = 0

    if count > 5:
        print("rebase_large")
    else:
        print("none")
    sys.exit(0)

# ── git stash pop ─────────────────────────────────────────────────────────────
if re.match(r'\bgit\b\s+stash\b.*\bpop\b', cmd):
    stash_diff = run(["git", "stash", "show", "-p", "stash@{0}"])
    lines = len(stash_diff.splitlines()) if stash_diff else 0
    if lines > auto_nudge_lines:
        print("stash_large")
    else:
        print("none")
    sys.exit(0)

print("none")
PYEOF

result=$(python3 "$_tmppy" "$cmd" "$auto_nudge_lines" "$auto_nudge_files" "$critical_paths" 2>/dev/null) || { rm -f "$_tmppy"; exit 0; }
rm -f "$_tmppy"

case "$result" in
  push)
    cat <<'MSG'
temper: about to push — have you run /temper to review your changes?
  Run /temper first, then push.
  Append  # temper:skip  (or  # suite:skip) to your push command to bypass this check.
MSG
    exit 1
    ;;
  commit_large)
    cat <<'MSG'
temper: large commit detected — consider running /temper first.
  Your staged diff exceeds the size threshold (lines or files).
  Append  # temper:skip  (or  # suite:skip) to your commit command to bypass this check.
MSG
    exit 1
    ;;
  commit_critical)
    cat <<'MSG'
temper: critical path file detected in staged changes — run /temper first.
  One or more staged files matches a critical path pattern (auth, schema, migrations, credentials).
  Append  # temper:skip  (or  # suite:skip) to your commit command to bypass this check.
MSG
    exit 1
    ;;
  merge_primary)
    cat <<'MSG'
temper: merging into a primary branch — consider running /temper --diff=all first.
  Merges into main/master/develop/trunk have high surface area.
  Append  # temper:skip  (or  # suite:skip) to your merge command to bypass this check.
MSG
    exit 1
    ;;
  rebase_large)
    cat <<'MSG'
temper: interactive rebase touching many commits — consider /temper --diff=all after.
  Append  # temper:skip  (or  # suite:skip) to your rebase command to bypass this check.
MSG
    exit 1
    ;;
  stash_large)
    cat <<'MSG'
temper: large stash detected — consider running /temper before committing.
  Your stash exceeds the size threshold. Apply it, then run /temper before committing.
  Append  # temper:skip  (or  # suite:skip) to your stash pop command to bypass this check.
MSG
    exit 1
    ;;
esac

exit 0
