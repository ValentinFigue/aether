#!/usr/bin/env bash
# Blocks sed/awk on .py/.ts/.tsx files and redirects to the appropriate bonsai tool.
INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', d)
print(ti.get('command', '') if isinstance(ti, dict) else '')
" 2>/dev/null || true)

if echo "$CMD" | grep -qE '(sed|awk)[[:space:]][^|&;]*\.(py|ts|tsx)'; then
  echo '{"decision":"block","reason":"sed/awk are text-blind on source files — use a bonsai tool instead:\n  rename symbol  → pyrename / tsrename\n  move file      → pymove / tsmove\n  move symbol    → pymovesymbol / tsmovesymbol\n  signature      → pysignature / tssignature\n  find refs      → pyfindrefs / tsfindrefs"}'
  exit 0
fi

echo '{"decision":"allow"}'
