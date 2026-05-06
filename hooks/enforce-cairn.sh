#!/usr/bin/env bash
# enforce-cairn.sh — PreToolUse command hook (matcher: Bash)
#
# Nudges the agent to use /cairn-commit instead of writing a weak git commit message.
# Exit 1 = allow the command but show the nudge as informational context.
# Exit 0 = allow silently (no weak message detected, or # cairn:skip bypass present).
#
# Bypass: append  # cairn:skip  to any command to silence this nudge.
# Bash treats it as a comment and ignores it at runtime.

set -euo pipefail

input=$(cat)

# If python3 fails for any reason (empty stdin, parse error), allow silently.
cmd=$(printf '%s' "$input" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('command', ''))
" 2>/dev/null) || exit 0

[ -z "$cmd" ] && exit 0

# Bypass marker: agent appends "# cairn:skip" when no better alternative exists.
if printf '%s' "$cmd" | grep -q '# *cairn:skip'; then
  exit 0
fi

# Write the checker to a temp file to avoid bash quote-tracking issues
# inside $() command substitution with heredoc (bash parses " inside $(...)).
_tmppy=$(mktemp /tmp/cairn_check.XXXXXX.py)
cat > "$_tmppy" << 'PYEOF'
import re, sys

cmd = sys.argv[1]

# Only trigger on git commit with an inline message flag
if not re.search(r'\bgit\b.*\bcommit\b', cmd):
    print("none")
    sys.exit(0)

if not re.search(r'(-m|--message)\s*.+', cmd):
    print("none")
    sys.exit(0)

# Extract the commit message value
m = re.search(r'(?:-m|--message)\s*["\']?([^"\']+)["\']?', cmd)
if not m:
    print("none")
    sys.exit(0)

msg = m.group(1).strip()

WEAK_WORDS = {
    "fix", "wip", "misc", "update", "changes", "stuff",
    "test", "temp", "tmp", "commit", "save", "done", "ok"
}

# Flag as weak if: very short, single word with no conventional prefix, or known weak word
is_short     = len(msg) < 10
is_weak_word = msg.lower().rstrip(".,!") in WEAK_WORDS
is_no_prefix = bool(re.match(r'^[a-zA-Z]+$', msg.split()[0])) and ':' not in msg

if is_short or is_weak_word or is_no_prefix:
    print("match")
else:
    print("none")
PYEOF

result=$(python3 "$_tmppy" "$cmd" 2>/dev/null) || { rm -f "$_tmppy"; exit 0; }
rm -f "$_tmppy"

if [ "$result" = "match" ]; then
  cat <<'MSG'
Cairn nudge: consider using /cairn-commit to generate a semantic commit message.
  git commit -m "fix"  ->  /cairn-commit  (stage your changes, then paste the suggested message)

If you want to commit with this message anyway, append  # cairn:skip  to silence this.
MSG
  exit 1
fi

exit 0
