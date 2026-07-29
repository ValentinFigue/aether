#!/usr/bin/env bash
# enforce-suite.sh — aether PreToolUse hook (matcher: Bash|Write|Edit|MultiEdit)
#
# Single coordinated gate chain covering all four suite plugins:
#   whetstone  (plan gate)   — git commit/push when plan exists but no critique
#   bonsai     (AST gate)    — text tools used on source files
#   temper     (review gate) — large/critical git commit; git push; merge/rebase
#   cairn      (ship gate)   — weak commit messages; git push without PR prep
#
# This file is a dispatcher, not a rulebook. Each gate lives in exactly one
# place — its own plugin's hooks/enforce-<plugin>.sh — and is sourced here with
# SUITE_MODE=1, which suppresses that file's standalone entrypoint and leaves
# just a gate_<plugin> function behind. Before this, the suite carried its own
# copy of all four gates and every rule change had to be made twice.
#
# Bypass markers (append as inline bash comment — bash ignores them at runtime):
#   # aether:skip  or  # suite:skip  — silence all gates
#   # whetstone:skip                 — silence whetstone only
#   # bonsai:skip                    — silence bonsai only
#   # temper:skip                    — silence temper only
#   # cairn:skip                     — silence cairn only
#
# Exit 1 = show message (non-blocking nudge, except temper which blocks high-risk ops).
# Exit 0 = allow silently.

set -euo pipefail

# ── Locate the gates ─────────────────────────────────────────────────────────
# Installed layout puts copies next to this file, so the hook is self-contained
# and never has to look up where the clone lives. Falling back to the repo
# layout keeps a checkout runnable in place, which is what the test suite uses.

_suite_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE_DIR="${AETHER_GATE_DIR:-$_suite_dir/gates}"

_gate_file() {
  local plugin="$1"
  if [ -f "$GATE_DIR/enforce-$plugin.sh" ]; then
    printf '%s' "$GATE_DIR/enforce-$plugin.sh"
  elif [ -f "$_suite_dir/../plugins/$plugin/hooks/enforce-$plugin.sh" ]; then
    printf '%s' "$_suite_dir/../plugins/$plugin/hooks/enforce-$plugin.sh"
  fi
}

# ── Parse stdin ──────────────────────────────────────────────────────────────

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

[ -z "${tool_name:-}" ] && exit 0
cmd_or_path="${cmd_or_path:-}"

# ── Bypass resolution ────────────────────────────────────────────────────────

bypass_all=false
bypass_whetstone=false
bypass_bonsai=false
bypass_temper=false
bypass_cairn=false

printf '%s' "$cmd_or_path" | grep -qE '#[[:space:]]*(aether|suite):skip'    && bypass_all=true
printf '%s' "$cmd_or_path" | grep -qE '#[[:space:]]*whetstone:skip'          && bypass_whetstone=true
printf '%s' "$cmd_or_path" | grep -qE '#[[:space:]]*bonsai:skip'             && bypass_bonsai=true
printf '%s' "$cmd_or_path" | grep -qE '#[[:space:]]*temper:skip'             && bypass_temper=true
printf '%s' "$cmd_or_path" | grep -qE '#[[:space:]]*cairn:skip'              && bypass_cairn=true

$bypass_all && exit 0

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

# ── Plugin enabled check ─────────────────────────────────────────────────────
# Sourcing the reader here also means the gates get it for free.

_plugin_enabled() {
  [ "$(aether_cfg_get "$1" enabled)" = "false" ] && return 1
  return 0
}

# ── Load the gates ───────────────────────────────────────────────────────────
# SUITE_MODE is exported before sourcing rather than used as an assignment
# prefix on `.`, whose persistence differs between bash's POSIX and default
# modes. A missing gate file is not an error — the suite degrades to whichever
# plugins are actually installed.
#
# -e is dropped *before* the loop, not after it. This hook runs on every Bash,
# Write and Edit call, and a gate file that is corrupt or half-written (an
# interrupted install, a full disk) makes sourcing fail. Under -e that aborted
# the hook with exit 2, which Claude Code treats as "block the tool call" — one
# bad file would have locked the user out of every command. Stderr is discarded
# for the same reason: a broken gate must degrade to silence, never to noise on
# every prompt. `aether status` reports gates that fail to parse.

set +e
export SUITE_MODE=1
for _p in whetstone bonsai temper cairn; do
  _f=$(_gate_file "$_p")
  [ -n "$_f" ] && . "$_f" 2>/dev/null
done
unset _p _f

# ── Dispatch ─────────────────────────────────────────────────────────────────
# Run gates in pipeline order, accumulating exit codes so one git command can
# surface several nudges at once.

# _run_gate <plugin> <gate-fn> <bypass-flag>
# Centralises the bypass and enabled checks that each inline gate used to
# repeat, and skips cleanly when a plugin is not installed.
_run_gate() {
  local plugin="$1" fn="$2" bypass="$3"
  [ "$bypass" = true ] && return 0
  _plugin_enabled "$plugin" || return 0
  declare -F "$fn" >/dev/null 2>&1 || return 0
  "$fn"
}

# -e is already off (see the gate-loading section). The gates are written to run
# without it, so a non-zero intermediate command inside one cannot abort the
# hook — that is the fail-open guarantee.

_exit=0

case "$tool_name" in
  Bash)
    _run_gate whetstone gate_whetstone "$bypass_whetstone" || _exit=1
    _run_gate bonsai    gate_bonsai    "$bypass_bonsai"    || _exit=1
    _run_gate temper    gate_temper    "$bypass_temper"    || _exit=1
    _run_gate cairn     gate_cairn     "$bypass_cairn"     || _exit=1
    ;;
  Write|Edit|MultiEdit)
    # bonsai, temper and cairn only ever inspect Bash commands. whetstone's
    # single gate handles both paths by branching on $tool_name, replacing the
    # separate gate_whetstone_write the suite used to carry.
    _run_gate whetstone gate_whetstone "$bypass_whetstone" || _exit=1
    ;;
esac

exit $_exit
