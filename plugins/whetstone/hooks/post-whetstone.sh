#!/usr/bin/env bash
# post-whetstone.sh — PostToolUse hook
# Matcher: Write|Edit|MultiEdit
#
# Records which plan this project is working on, and nothing else.
#
# It exists because `~/.claude/plans/` is shared by every project on the machine and
# nothing in a filename says which repo a plan belongs to. Before this, the gate
# globbed `./.claude/plans/*.md` and so never saw a plan written by plan mode at all —
# it compared whatever stale plan happened to be in the project directory instead.
#
# Deliberately silent. Plan mode writes the plan file repeatedly while the plan is
# being built, so a nudge here would fire on every keystroke's worth of edit. The
# nudging belongs where it means something: presenting the plan, the first source
# write, and `git commit`.
#
# Always exits 0. A PostToolUse hook has nothing to gate.

set +e

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
for _lib in "$_here/../aether-config.sh" "$_here/aether-config.sh" \
            "$_here/../../../hooks/aether-config.sh" \
            "${AETHER_HOME:-$HOME/.aether}/hooks/aether-config.sh"; do
  # shellcheck source=/dev/null
  [ -f "$_lib" ] && { . "$_lib"; break; }
done
unset _lib _here
command -v aether_plan_pointer >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null)
[ -n "$input" ] || exit 0

path=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print(""); raise SystemExit
inp = d.get("tool_input") or {}
print(inp.get("file_path") or inp.get("path") or "")
' 2>/dev/null) || exit 0
[ -n "$path" ] || exit 0

# A plan is any .md under a plans directory, project-local or the global one plan mode
# uses. CRITIQUE.md and TEMPER.md are generated output that happens to live nearby.
case "$path" in
  *.md) ;;
  *) exit 0 ;;
esac
case "$path" in
  */.claude/plans/*|.claude/plans/*) ;;
  *) exit 0 ;;
esac
case "$(basename "$path")" in
  CRITIQUE.md|TEMPER.md|.*) exit 0 ;;
esac

ptr=$(aether_plan_pointer)
mkdir -p "$(dirname "$ptr")" 2>/dev/null || exit 0
# Absolute, because the gate may run from a different directory than the write did.
case "$path" in
  /*) printf '%s\n' "$path" > "$ptr" 2>/dev/null ;;
  *)  printf '%s\n' "$(pwd -P)/$path" > "$ptr" 2>/dev/null ;;
esac

exit 0
