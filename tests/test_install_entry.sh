#!/usr/bin/env bash
# tests/test_install_entry.sh — the install.sh / uninstall.sh entry points.
#
# Agents are named, never defaulted: the entry points refuse to run without
# at least one of --claude / --vibe / --codex, so no agent is silently the
# assumed one. Three properties carry the weight:
#
#   1. The refusal writes nothing — a failed invocation must not leave half
#      an install behind.
#   2. --vibe alone touches nothing Claude-related, and --claude alone
#      touches nothing in ~/.vibe or ~/.codex.
#   3. --claude routes the remaining arguments to the engine unchanged — the
#      engine's own contract, reached through the wrapper.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

suite "install entry"

H=$(mktemp -d)
trap 'rm -rf "$H"' EXIT
entry()    { env HOME="$H" bash "$REPO/install.sh" "$@"; }
unentry()  { env HOME="$H" bash "$REPO/uninstall.sh" "$@"; }

# ── the refusal ─────────────────────────────────────────────────────────────

out=$(entry 2>&1); rc=$?
assert_exit 1 "$rc" "no agent flag refuses to run"
assert_contains "$out" "--claude" "the refusal names Claude Code"
assert_contains "$out" "--vibe"  "the refusal names Vibe Code"
assert_contains "$out" "--codex" "the refusal names Codex"
if [ -e "$H/.claude" ] || [ -e "$H/.vibe" ] || [ -e "$H/.codex" ]; then
  fail "the refusal writes nothing"
else
  pass "the refusal writes nothing"
fi

out=$(unentry 2>&1); rc=$?
assert_exit 1 "$rc" "uninstall with no agent flag refuses to run"

# --dry-run promises that nothing is written; composed with a skills target it
# would install for real, so the combination is refused before anything runs.
out=$(entry --vibe --global --dry-run 2>&1); rc=$?
assert_exit 1 "$rc" "--dry-run with --vibe refuses to run"
if [ -e "$H/.vibe" ]; then
  fail "the --dry-run refusal writes nothing"
else
  pass "the --dry-run refusal writes nothing"
fi

out=$(entry --claude --vibe --dry-run 2>&1); rc=$?
assert_exit 1 "$rc" "--dry-run with --claude --vibe refuses to run"

# ── one agent at a time ─────────────────────────────────────────────────────

entry --vibe >/dev/null
n=$(find "$H/.vibe/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "11" "$n" "--vibe installs the eleven skills"
if [ -e "$H/.claude" ]; then
  fail "--vibe alone touches nothing Claude-related"
else
  pass "--vibe alone touches nothing Claude-related"
fi

# --claude routes through to the engine; --dry-run proves the routing without
# writing anything, the same way the acceptance suite uses it.
out=$(entry --claude --global --dry-run 2>&1); rc=$?
assert_exit 0 "$rc" "--claude routes the engine install"
assert_contains "$out" "[dry-run]" "engine arguments reach the engine"
if [ -e "$H/.claude" ]; then
  fail "--claude --dry-run writes nothing"
else
  pass "--claude --dry-run writes nothing"
fi
if [ -d "$H/.codex/skills" ]; then
  fail "--claude alone touches nothing in the other agents"
else
  pass "--claude alone touches nothing in the other agents"
fi

# ── composition ──────────────────────────────────────────────────────────────

# A real compose: --dry-run is refused with --vibe/--codex, so the engine
# install runs for real here (throwaway HOME, bonsai skipped).
entry --claude --vibe --codex --global --no-bonsai >/dev/null 2>&1
vibe_n=$(find "$H/.vibe/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
codex_n=$(find "$H/.codex/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "11" "$vibe_n" "all three agents compose: vibe installs"
assert_eq "11" "$codex_n" "all three agents compose: codex installs"

unentry --vibe --codex >/dev/null
if [ -d "$H/.vibe/skills" ] || [ -d "$H/.codex/skills" ]; then
  fail "uninstall --vibe --codex removes both skill sets"
else
  pass "uninstall --vibe --codex removes both skill sets"
fi

# Engine-only options with no --claude are not silently ignored.
out=$(entry --vibe --global 2>&1)
assert_contains "$out" "add --claude" "engine-only options without --claude are flagged"

# The uninstall path flags them too, rather than letting a --global look like
# it removed the global install.
out=$(unentry --vibe --global --claude-md 2>&1)
assert_contains "$out" "add --claude" "uninstall flags engine options without --claude"

summary
