#!/usr/bin/env bash
# Blocks sed/awk/grep/find on .py/.ts/.tsx files and redirects to bonsai tools.
INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', d)
print(ti.get('command', '') if isinstance(ti, dict) else '')
" 2>/dev/null || true)

if echo "$CMD" | grep -qE '(sed|awk)[[:space:]][^|&;]*\.(py|ts|tsx)'; then
  echo '{"decision":"block","reason":"sed/awk are text-blind on source files — use a bonsai tool instead:\n  rename symbol  → pyrename / tsrename\n  move file      → pymove / tsmove\n  move symbol    → pymovesymbol / tsmovesymbol\n  signature      → pysignature / tssignature"}'
  exit 0
fi

if echo "$CMD" | grep -qE 'grep[[:space:]].*\.(py|ts|tsx)'; then
  echo '{"decision":"block","reason":"grep on source files misses AST context — use a bonsai tool instead:\n  find all usages → pyfindrefs / tsfindrefs\n  find call sites → pycallers\n  text search     → pygrep (respects project layout)\n  dead code       → pyfindunused"}'
  exit 0
fi

if echo "$CMD" | grep -qE 'find[[:space:]].*-name[[:space:]][^[:space:]]*\.(py|ts|tsx)'; then
  echo '{"decision":"block","reason":"find on source files — use a bonsai tool instead:\n  find symbol usages  → pyfindrefs / tsfindrefs\n  find unused symbols → pyfindunused\n  text search         → pygrep"}'
  exit 0
fi

echo '{"decision":"allow"}'
