#!/usr/bin/env bash
# enforce-bonsai.sh — PreToolUse command hook (matcher: Bash)
#
# Nudges the agent to use bonsai AST tools instead of text tools on source files.
# Exit 1 = allow the command but show the nudge as informational context.
# Exit 0 = allow silently (no nudge needed, or # bonsai:skip bypass present).
#
# Bypass: append  # bonsai:skip  to any command to silence this nudge.
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

# Bypass marker: agent appends "# bonsai:skip" when no bonsai alternative exists.
if printf '%s' "$cmd" | grep -q '# *bonsai:skip'; then
  exit 0
fi

match=$(python3 - "$cmd" <<'PYEOF'
import re, sys
cmd = sys.argv[1]
TOOL_RE = re.compile(r'\b(grep|sed|awk|find)\b')
EXT_RE  = re.compile(r'\.(py|tsx|ts)\b')
print("match" if TOOL_RE.search(cmd) and EXT_RE.search(cmd) else "none")
PYEOF
) || exit 0

if [ "$match" = "match" ]; then
  cat <<'MSG'
Bonsai nudge: consider an AST tool instead of text tools on source files.
  grep/find .py/.ts  →  pyfindrefs, pygrep, pyfindunused / tsfindrefs
  sed/awk rename     →  pyrename / tsrename
  move file          →  pymove / tsmove

If no bonsai tool covers your use case, append  # bonsai:skip  to silence this.
MSG
  exit 1
fi

exit 0
