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

# ── Config reader ────────────────────────────────────────────────────────────
# One parser, shared with bin/aether. Under the suite it is already sourced by
# enforce-suite.sh; standalone this finds it. A gate that cannot find it must
# still run — every config key has a default, so the gate degrades to those
# rather than going silent.
if ! command -v aether_cfg_get >/dev/null 2>&1; then
  _ac_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
  for _ac in "$_ac_here/../aether-config.sh" "$_ac_here/aether-config.sh" \
             "$_ac_here/../../../hooks/aether-config.sh" \
             "${AETHER_HOME:-$HOME/.aether}/hooks/aether-config.sh"; do
    [ -f "$_ac" ] && { . "$_ac"; break; }
  done
  unset _ac _ac_here
  if ! command -v aether_cfg_get >/dev/null 2>&1; then
    aether_cfg_get() { :; }
    aether_out_dir() { [ -d .aether ] && printf '.aether/out' || printf '%s/out' "${AETHER_HOME:-$HOME/.aether}"; }
  fi
fi

# Generated output lives under .aether/out/ now. The pre-migration path is still
# honoured so the gate does not start nagging on a machine that has not upgraded
# yet — for a user who never runs the migration, nothing changes.
CRITIQUE_FILE="$(aether_out_dir 2>/dev/null)/CRITIQUE.md"
[ -f "$CRITIQUE_FILE" ] || [ ! -f .claude/plans/CRITIQUE.md ] || CRITIQUE_FILE=".claude/plans/CRITIQUE.md"

# Nudge at most once per uncritiqued plan *version*, not once per project for ever.
# The old sentinel was a single empty file, so after the first nudge this gate was
# decorative — silent for every later plan, in every later month.
_ws_nudged() {
  local key="$1" f=".aether/out/.nudged"
  [ -f "$f" ] && grep -qxF "$key" "$f" 2>/dev/null && return 0
  # Pre-1.4 sentinel: an empty marker file meaning "this project was nudged once".
  # Honoured so an existing project does not get one fresh nudge on upgrade.
  [ -f .claude/plans/.whetstone-nudged ] && return 0
  [ -s "$f" ] || [ ! -f "$f" ] || return 0
  return 1
}
_ws_mark_nudged() {
  local key="$1" f=".aether/out/.nudged"
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  printf '%s\n' "$key" >> "$f" 2>/dev/null || true
}

# Records that this gate has ever seen an ExitPlanMode payload. Whether Claude Code
# delivers PreToolUse for that tool could not be determined from outside, so rather
# than guess, the gate reports what it observes and `aether plan status` prints it.
_ws_seen_exitplanmode() {
  local f=".aether/out/.exitplanmode-seen"
  [ -f "$f" ] && return 0
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$f" 2>/dev/null || true
  return 0
}

# ── Gate ─────────────────────────────────────────────────────────────────────
# Reads: $tool_name, $cmd_or_path.  Returns: 1 to nudge, 0 to stay silent.
# Serves the Bash, Write/Edit/MultiEdit and ExitPlanMode paths from one function.
gate_whetstone() {
  local tool="${tool_name:-}" target="${cmd_or_path:-}"
  [ -z "$tool" ] && return 0

  # Bypass markers
  printf '%s' "$target" | grep -qE '#\s*(whetstone|suite):skip' && return 0

  local plan state
  plan=$(aether_plan_file 2>/dev/null) || plan=""
  state=$(aether_plan_state "$plan" 2>/dev/null) || state=none

  # ── ExitPlanMode: the moment the critique should already exist ──────────────
  #
  # Returns 0 unconditionally — it prints, it never gates. Whether a non-zero exit
  # would block leaving plan mode is not knowable from here, and a nudge that traps
  # you in the mode it is nudging about, while intercepting the very tool calls the
  # critique needs, would be far worse than no nudge at all.
  if [ "$tool" = ExitPlanMode ]; then
    _ws_seen_exitplanmode
    case "$state" in
      uncritiqued)
        printf 'Whetstone: this plan has no critique on record.\n'
        printf '  Run /critique-plan before presenting it — blockers are cheapest now.\n' ;;
      stale)
        printf 'Whetstone: the plan changed after its last critique.\n'
        printf '  Re-run /critique-plan on the current version.\n' ;;
    esac
    return 0
  fi

  # ── git push or commit ─────────────────────────────────────────────────────
  if printf '%s' "$target" | grep -qE '^git (push|commit)'; then
    [ -n "$plan" ] || return 0

    # A plan carrying its own critique settles it without any generated file, which
    # is the plan-mode case: nothing but the plan is writable there.
    case "$state" in
      critiqued) return 0 ;;
      uncritiqued)
        # Pre-1.4 state: no in-plan marker, but a CRITIQUE.md newer than the plan.
        # Kept so a project that critiqued the old way is not told to do it again.
        if [ -f "$CRITIQUE_FILE" ] && [ ! -f "$(aether_plan_pointer)" ]; then
          python3 -c "
import os, sys
sys.exit(0 if os.path.getmtime('$plan') <= os.path.getmtime('$CRITIQUE_FILE') else 1)
" 2>/dev/null && return 0
        fi
        printf 'Whetstone: a plan exists but has not been critiqued yet.\n'
        printf '  %s\n' "$plan"
        printf '  Run /critique-plan before committing to surface blockers now.\n'
        printf '  Append  # whetstone:skip  to your git command to bypass.\n'
        return 1 ;;
      stale)
        printf 'Whetstone: the plan changed after its last critique.\n'
        printf '  %s\n' "$plan"
        printf '  Re-run /critique-plan on the updated plan before committing.\n'
        printf '  Append  # whetstone:skip  to your git command to bypass.\n'
        return 1 ;;
    esac
    return 0
  fi

  # ── first source-file write with no critique on record ─────────────────────
  if printf '%s' "$tool" | grep -qE '^(Write|Edit|MultiEdit)$'; then
    local is_source key
    is_source=$(python3 -c "
import re, sys
print('yes' if re.search(r'\.(py|ts|tsx|js|jsx|mjs)$', sys.argv[1]) else 'no')
" "$target" 2>/dev/null) || return 0
    [ "$is_source" = yes ] || return 0

    case "$state" in critiqued) return 0 ;; none) ;; esac
    # Keyed on the plan's own hash, so a second uncritiqued plan nudges again while
    # the same one never nudges twice.
    key="$(aether_plan_hash "$plan" 2>/dev/null)"
    key="${key:-noplan}"
    _ws_nudged "$key" && return 0
    _ws_mark_nudged "$key"

    if [ -n "$plan" ]; then
      printf 'Whetstone: writing source with no critiqued plan on record.\n'
      printf '  %s\n' "$plan"
    else
      printf 'Whetstone: writing source code with no critiqued plan on record.\n'
    fi
    printf '  If this is a planned change, run /critique-plan first.\n'
    printf '  Append  # whetstone:skip  to your path to bypass.\n'
    return 1
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
