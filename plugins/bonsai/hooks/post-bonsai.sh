#!/usr/bin/env bash
# post-bonsai.sh — PostToolUse hook (matcher: Write|Edit|MultiEdit)
#
# After a file write/edit on a source file, nudges to verify reference
# integrity if the change looks like a rename or signature modification.
#
# Exit 1 = show nudge (informational, non-blocking).
# Exit 0 = allow silently.

set -euo pipefail

input=$(cat)

result=$(printf '%s' "$input" | python3 -c "
import json, re, sys

data   = json.load(sys.stdin)
path   = data.get('tool_input', {}).get('path', '')
patch  = data.get('tool_input', {}).get('new_content', '') \
       + data.get('tool_input', {}).get('new_str', '')

SRC_RE = re.compile(r'\.(py|ts|tsx|js|jsx)$')
if not SRC_RE.search(path):
    print('none'); sys.exit()

RENAME_RE = re.compile(r'^\+.*(def |function |class |const |export )', re.MULTILINE)
SIG_RE    = re.compile(r'^\+.*def .*\(.*\).*:', re.MULTILINE)

if SIG_RE.search(patch):
    print('signature')
elif RENAME_RE.search(patch):
    print('rename')
else:
    print('none')
" 2>/dev/null) || exit 0

case "$result" in
  rename)
    cat <<'MSG'
Bonsai post-edit: a symbol definition changed — verify references are consistent.
  pyfindrefs <symbol>  or  tsfindrefs <symbol>
  If you renamed the symbol, use  pyrename / tsrename  to update all call sites.
MSG
    exit 1
    ;;
  signature)
    cat <<'MSG'
Bonsai post-edit: a function signature changed — verify all call sites still match.
  pysignature / tssignature  propagates parameter changes to callers.
  pyfindrefs <fn_name>  shows every call site to review manually.
MSG
    exit 1
    ;;
esac

exit 0
