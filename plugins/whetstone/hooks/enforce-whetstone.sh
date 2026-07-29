#!/usr/bin/env bash
# enforce-whetstone.sh — PreToolUse hook
# Matcher: Bash|Write|Edit|MultiEdit
#
# Gate 1 (Bash): nudges on git push/commit when no critique exists or critique is stale.
# Gate 2 (Write/Edit/MultiEdit): nudges once per project on first source-file write
#                                 when no critique is on record.
#
# Both gates are non-blocking: exit 1 shows a message; the tool call still proceeds.
# Bypass: append  # whetstone:skip  or  # suite:skip  to silence.
#
# Dual mode. Standalone, the entrypoint at the bottom reads stdin and exits.
# Under the aether suite, enforce-suite.sh sources this file with SUITE_MODE=1
# and calls gate_whetstone with $tool_name / $cmd_or_path already parsed.

CRITIQUE_FILE=".claude/plans/CRITIQUE.md"

# ── Gate ─────────────────────────────────────────────────────────────────────
# Reads: $tool_name, $cmd_or_path.  Returns: 1 to nudge, 0 to stay silent.
# Handles both the Bash and the Write/Edit/MultiEdit paths — the suite calls
# this one function for either, rather than keeping two separate entry points.
gate_whetstone() {
  local tool="${tool_name:-}" target="${cmd_or_path:-}"
  [ -z "$tool" ] && return 0

  # Bypass markers
  printf '%s' "$target" | grep -qE '#\s*(whetstone|suite):skip' && return 0

  # ── Gate 1: git push or commit ─────────────────────────────────────────────
  if printf '%s' "$target" | grep -qE '^git (push|commit)'; then
    # Find the newest plan file in .claude/plans/ (any .md except CRITIQUE.md)
    local plan_file stale
    plan_file=$(python3 -c '
import os, glob
plans = [f for f in glob.glob(".claude/plans/*.md")
         if os.path.basename(f) not in ("CRITIQUE.md",)
         and not os.path.basename(f).startswith(".")]
print(max(plans, key=os.path.getmtime) if plans else "")
' 2>/dev/null) || plan_file=""

    if [ -n "$plan_file" ] && [ ! -f "$CRITIQUE_FILE" ]; then
      printf 'Whetstone: a plan exists but has not been critiqued yet.\n'
      printf '  Run /critique-plan before committing to surface blockers now.\n'
      printf '  Append  # whetstone:skip  to your git command to bypass.\n'
      return 1
    fi

    if [ -n "$plan_file" ] && [ -f "$CRITIQUE_FILE" ]; then
      stale=$(python3 -c "
import os
plan = os.path.getmtime('$plan_file')
crit = os.path.getmtime('$CRITIQUE_FILE')
print('stale' if plan > crit else 'ok')
" 2>/dev/null) || return 0
      if [ "$stale" = "stale" ]; then
        printf 'Whetstone: plan was modified after the last critique — critique is stale.\n'
        printf '  Re-run /critique-plan on the updated plan before committing.\n'
        printf '  Append  # whetstone:skip  to your git command to bypass.\n'
        return 1
      fi
    fi

    return 0
  fi

  # ── Gate 2: first source-file write with no critique on record ─────────────
  if printf '%s' "$tool" | grep -qE '^(Write|Edit|MultiEdit)$'; then
    local is_source sentinel
    is_source=$(python3 -c "
import re, sys
print('yes' if re.search(r'\.(py|ts|tsx|js|jsx|mjs)$', sys.argv[1]) else 'no')
" "$target" 2>/dev/null) || return 0

    if [ "$is_source" = "yes" ] && [ ! -f "$CRITIQUE_FILE" ]; then
      sentinel=".claude/plans/.whetstone-nudged"
      [ -f "$sentinel" ] && return 0
      touch "$sentinel" 2>/dev/null || true
      printf 'Whetstone: writing source code with no critiqued plan on record.\n'
      printf '  If this is a planned change, run /critique-plan first.\n'
      printf '  Append  # whetstone:skip  to your path to bypass.\n'
      return 1
    fi
  fi

  return 0
}

# ── Standalone entrypoint ────────────────────────────────────────────────────
# Skipped when sourced by enforce-suite.sh. `set -e` lives here rather than at
# file scope so sourcing cannot change the caller's shell options.
if [ -z "${SUITE_MODE:-}" ]; then
  set -euo pipefail

  input=$(cat)

  eval "$(printf '%s' "$input" | python3 -c '
import json, sys, shlex
data = json.loads(sys.stdin.read())
tool = data.get("tool_name", "")
inp  = data.get("tool_input", {})
val  = inp.get("command", "") or inp.get("file_path", "")
print("tool_name=" + shlex.quote(tool))
print("cmd_or_path=" + shlex.quote(val))
' 2>/dev/null)" || exit 0

  gate_whetstone
  exit $?
fi
