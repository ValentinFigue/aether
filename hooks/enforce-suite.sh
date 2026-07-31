#!/usr/bin/env bash
# enforce-suite.sh — aether PreToolUse hook.
#
# The matcher is the union of every suite_owned PreToolUse matcher the plugin
# manifests declare — see _suite_matcher in bin/aether. Today that is
# Bash|Write|Edit|MultiEdit|ExitPlanMode.
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

# ── Config reader ────────────────────────────────────────────────────────────
# One parser, shared with bin/aether, and sourcing it here means the gates get it
# for free. The engine installs it beside this file, and $_suite_dir is already
# resolved above — so no extra process is spawned to find it. The generic search
# below is only for an install that predates the file.
if [ -f "$_suite_dir/aether-config.sh" ]; then
  # shellcheck source=/dev/null
  . "$_suite_dir/aether-config.sh"
elif [ -f "${AETHER_HOME:-$HOME/.aether}/hooks/aether-config.sh" ]; then
  # shellcheck source=/dev/null
  . "${AETHER_HOME:-$HOME/.aether}/hooks/aether-config.sh"
fi
# A gate that cannot find it must still run: every key has a default, so the
# gates degrade to those rather than going silent.
# Read both config files once, here, rather than once per key below.
command -v aether_cfg_preload >/dev/null 2>&1 && aether_cfg_preload
if ! command -v aether_cfg_resolve >/dev/null 2>&1; then
  aether_cfg_resolve() { AETHER_CFG_VALUE=""; }
  aether_cfg_get()     { :; }
  aether_out_dir()     { [ -d .aether ] && printf '.aether/out' || printf '%s/out' "${AETHER_HOME:-$HOME/.aether}"; }
fi

# ── Parse stdin ──────────────────────────────────────────────────────────────
# One interpreter for the whole hook. This used to be the first of three python
# starts on a `git commit` — the other two were temper's and cairn's rules, both
# now bash. `tests/test_hookcost.sh` asserts the count stays at one.

input=$(cat)
command -v aether_parse_command >/dev/null 2>&1 || exit 0
aether_parse_command "$input" || exit 0
[ -z "${tool_name:-}" ] && exit 0

# ── Bypass resolution ────────────────────────────────────────────────────────
# Five greps became one shared answer. They had already drifted — `#\s*`, `# *`
# and `#[[:space:]]*` in three files — and all five matched the marker anywhere in
# the command, so `git commit -m "docs: explain # aether:skip"` silenced the suite.
# aether_bypassed only honours a marker in a trailing comment. See BYPASS.md.

aether_bypassed aether && exit 0

# ── Plugin enabled check ─────────────────────────────────────────────────────
# Sourcing the reader here also means the gates get it for free.

# No $( ) — this runs once per plugin on every tool call.
_plugin_enabled() {
  if command -v aether_cfg_resolve >/dev/null 2>&1; then
    aether_cfg_resolve "$1" enabled
    [ "$AETHER_CFG_VALUE" = "false" ] && return 1
  fi
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
# Gates run in lifecycle order — plan, build, review, ship — and their output is
# collected rather than printed. One `git commit` used to be able to emit fifteen
# lines from three plugins, which is how a guardrail teaches people to bypass it.
#
# The budget is: one nudge per tool call, the earliest stage wins, and a single
# line names who else had something to say. A **block** is exempt. Suppressing one
# would turn "you cannot push unreviewed" into "you might not hear about it", so a
# block prints in full and alone, and the nudges beside it are dropped entirely —
# being told you cannot push is the only thing that matters at that moment.

# _run_gate <plugin> <gate-fn>
# Centralises the bypass and enabled checks each inline gate used to repeat, skips
# cleanly when a plugin is not installed, and captures rather than prints.
#
# Return codes from a gate: 0 silent, 1 nudge, 2 block.
_run_gate() {
  local plugin="$1" fn="$2" out rc
  aether_bypassed "$plugin" && return 0
  _plugin_enabled "$plugin" || return 0
  declare -F "$fn" >/dev/null 2>&1 || return 0

  out=$("$fn" 2>/dev/null); rc=$?
  # Output, not the return code, is what decides whether a gate had something to
  # say. whetstone on ExitPlanMode prints and returns 0 on purpose — leaving plan
  # mode must never be gated — and an early `[ $rc -eq 0 ] && return 0` here
  # silently ate that message.
  [ -n "$out" ] || return 0
  [ "$rc" -ne 0 ] && spoke=1

  if [ "$rc" -ge 2 ]; then
    blocks="${blocks}${out}
"
  elif [ -z "$first_plugin" ]; then
    first_plugin="$plugin"
    first_nudge="$out"
  else
    others="$others $plugin"
    later="${later}## ${plugin}
${out}
"
  fi
  return 0
}

# -e is already off (see the gate-loading section). The gates are written to run
# without it, so a non-zero intermediate command inside one cannot abort the
# hook — that is the fail-open guarantee.

blocks=""
spoke=""
first_plugin=""
first_nudge=""
later=""
others=""

case "$tool_name" in
  Bash)
    _run_gate whetstone gate_whetstone
    _run_gate bonsai    gate_bonsai
    _run_gate temper    gate_temper
    _run_gate cairn     gate_cairn
    ;;
  Write|Edit|MultiEdit)
    # bonsai, temper and cairn only ever inspect Bash commands. whetstone's
    # single gate handles both paths by branching on $tool_name, replacing the
    # separate gate_whetstone_write the suite used to carry.
    _run_gate whetstone gate_whetstone
    ;;
  ExitPlanMode)
    # Only whetstone has anything to say when a plan is presented. Its gate returns 0
    # for this tool unconditionally — it prints and never gates — so leaving plan mode
    # can never be blocked.
    #
    # Widening the matcher in the manifest is not enough on its own: without this
    # branch the hook is invoked and dispatches nothing, which is how the trigger
    # first appeared to work and did not.
    _run_gate whetstone gate_whetstone
    ;;
esac

# ── One voice ────────────────────────────────────────────────────────────────

# Everything held back is recorded whether or not the summary line can point at
# it, so `aether status --notes` is useful in the block case too, where nothing
# announces that anything was suppressed.
_notes=$(aether_notes_file 2>/dev/null)
_suppressed="$later"
[ -n "$blocks" ] && [ -n "$first_plugin" ] && _suppressed="## $first_plugin
$first_nudge
$later"

if [ -n "$_notes" ] && [ -n "$_suppressed" ]; then
  mkdir -p "$(dirname "$_notes")" 2>/dev/null && printf '%s' "$_suppressed" > "$_notes" 2>/dev/null
fi

# ── Strict mode ──────────────────────────────────────────────────────────────
# A PreToolUse hook can stop a tool call two ways. Exit 2 is the blunt one, and it is
# exactly what bash returns for a syntax error — a deliberate block and a half-written
# file would be indistinguishable, which is why nothing here has ever used it.
#
# The other way is to exit 0 and print a decision. `ask` escalates to the human, and
# **the agent cannot answer it** — the first mechanism in this suite that takes the
# decision away from the thing writing the command. It needs no bypass marker either:
# approving the prompt is the bypass. And breakage cannot forge it, because a syntax
# error cannot print valid JSON and exit 0.
#
# Read from the global config only: a project-level switch would sit in the tree the
# agent is editing, and the entire value of this is that switching it off is conspicuous.
# aether_cfg_read reads the one file it is given, so naming the global file is what
# makes this global-only — no resolution, no project override.
if [ -n "$blocks" ] && \
   [ "$(aether_cfg_read "$(aether_cfg_file global)" temper strict 2>/dev/null)" = blocks ]; then
  _reason=$(printf '%s' "$blocks" | python3 -c 'import json,sys
r = sys.stdin.read().strip()
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": r}}))' 2>/dev/null)
  # Nothing else may reach stdout on this path or the JSON is corrupt. If python3 is
  # somehow gone, degrade to today's plain text rather than emit something malformed.
  if [ -n "$_reason" ]; then
    printf '%s\n' "$_reason"
    exit 0
  fi
fi

if [ -n "$blocks" ]; then
  printf '%s' "$blocks"
  exit 1
fi

[ -n "$first_nudge" ] || exit 0
printf '%s\n' "$first_nudge"
# Falls through to exit 0 when every gate that spoke also returned 0.

if [ -n "$others" ]; then
  # "temper", "temper and cairn", "bonsai, temper and cairn"
  _list=""
  for _o in $others; do
    if [ -z "$_list" ]; then _list="$_o"
    else _list="$_list, $_o"; fi
  done
  case "$_list" in
    *,*) _list="${_list%,*} and ${_list##*, }" ;;
  esac
  if [ -n "$_notes" ]; then
    printf '  + %s also had notes — `aether status --notes` to see them.\n' "$_list"
  else
    printf '  + %s also had notes.\n' "$_list"
  fi
fi

[ -n "$spoke" ] && exit 1
exit 0
