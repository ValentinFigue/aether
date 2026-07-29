#!/usr/bin/env bash
# enforce-bonsai.sh — PreToolUse hook (matcher: Bash)
#
# Intercepts two categories:
#   1. Text tools used on source files  (grep, sed, awk, find, rg, ag, perl, xargs)
#   2. File move/rename operations      (mv, git mv, cp)
#
# Bypass: append  # bonsai:skip  or  # suite:skip  to silence for that command.
# Bash treats it as a comment and ignores it at runtime.
# Exit 1 = allow the command but show the nudge as informational context.
# Exit 0 = allow silently.
#
# Dual mode. Standalone, the entrypoint at the bottom reads stdin and exits.
# Under the aether suite, enforce-suite.sh sources this file with SUITE_MODE=1
# and calls gate_bonsai with $cmd_or_path already parsed.

# ── Gate ─────────────────────────────────────────────────────────────────────
# Reads: $cmd_or_path.  Returns: 1 to nudge, 0 to stay silent.
gate_bonsai() {
  local cmd="${cmd_or_path:-}"
  [ -z "$cmd" ] && return 0

  # Bypass marker
  if printf '%s' "$cmd" | grep -qE '# *(bonsai|suite):skip'; then
    return 0
  fi

  # Classify the command into one of three operation types
  local result
  result=$(python3 - "$cmd" <<'PYEOF'
import re, sys
cmd = sys.argv[1]

SRC = r'\.(py|ts|tsx|js|jsx|mjs)(\b|$)'

# Category A — text search/read tools on source files
SEARCH_RE = re.compile(r'\b(grep|rg|ripgrep|ag|ack|pygrep|fgrep)\b')

# Category B — text mutation tools on source files
MUTATE_RE = re.compile(r'\b(sed|awk|perl)\b')

# Category C — move / rename / copy of source files
MOVE_RE   = re.compile(r'\b(mv|git\s+mv|cp)\b')

# Category D — xargs chains that pipe into mutation
XARGS_RE  = re.compile(r'\bxargs\b.*(sed|awk|perl)', re.DOTALL)

has_src = bool(re.search(SRC, cmd))

if MOVE_RE.search(cmd) and has_src:
    print("move")
elif (MUTATE_RE.search(cmd) or XARGS_RE.search(cmd)) and has_src:
    print("mutate")
elif SEARCH_RE.search(cmd) and has_src:
    print("search")
else:
    print("none")
PYEOF
) || return 0

  case "$result" in
    search)
      cat <<'MSG'
Bonsai nudge — searching source files:
  grep/rg on .py   →  pyfindrefs <symbol>  or  pygrep <pattern> (AST-aware, follows re-exports)
  grep/rg on .ts   →  tsfindrefs <symbol>  (catches type references grep misses)
  looking for dead code?  →  pyfindunused
Append  # bonsai:skip  if you need raw text search.
MSG
      return 1
      ;;
    mutate)
      cat <<'MSG'
Bonsai nudge — mutating source files with a text tool:
  sed/perl rename  →  pyrename <old> <new>  or  tsrename (safe: updates imports, types, re-exports)
  sed signature    →  pysignature / tssignature (propagates call-site changes)
  Text substitution silently breaks aliased imports and type references.
  Always dry-run first: pyrename --dry-run <old> <new>
Append  # bonsai:skip  if bonsai has no equivalent for your operation.
MSG
      return 1
      ;;
    move)
      cat <<'MSG'
Bonsai nudge — moving or copying a source file:
  mv / git mv .py  →  pymove <src> <dst>   (rewrites all import paths automatically)
  mv / git mv .ts  →  tsmove <src> <dst>
  Raw mv leaves all import statements pointing at the old path.
  Always dry-run first: pymove --dry-run <src> <dst>
Append  # bonsai:skip  if this is a new/untracked file with no importers.
MSG
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

# ── Standalone entrypoint ────────────────────────────────────────────────────
# Skipped when sourced by enforce-suite.sh. `set -e` lives here rather than at
# file scope so sourcing cannot change the caller's shell options.
if [ -z "${SUITE_MODE:-}" ]; then
  set -euo pipefail

  input=$(cat)

  # If python3 fails for any reason (empty stdin, parse error), allow silently.
  cmd_or_path=$(printf '%s' "$input" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('command', ''))
" 2>/dev/null) || exit 0

  gate_bonsai
  exit $?
fi
