#!/usr/bin/env bash
# tests/lib.sh — minimal assertion helpers.
#
# Deliberately dependency-free rather than bats: aether is pure shell and its
# selling point is "clone and run", so the test suite must not require a
# package install to execute here or in CI.

TESTS_RUN=0
TESTS_FAILED=0
CURRENT_SUITE=""

RED=$'\033[31m'; GREEN=$'\033[32m'; DIM=$'\033[2m'; RESET=$'\033[0m'
[ -t 1 ] || { RED=""; GREEN=""; DIM=""; RESET=""; }

suite() {
  CURRENT_SUITE="$1"
  printf '\n%s── %s ──%s\n' "$DIM" "$1" "$RESET"
}

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  %s✗%s %s\n' "$RED" "$RESET" "$1"
  shift
  for line in "$@"; do printf '      %s\n' "$line"; done
}

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$msg"
  else
    fail "$msg" "expected: $expected" "actual:   $actual"
  fi
}

assert_exit() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$expected" -eq "$actual" ]; then
    pass "$msg"
  else
    fail "$msg" "expected exit $expected, got $actual"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  case "$haystack" in
    *"$needle"*) pass "$msg" ;;
    *) fail "$msg" "expected output to contain: $needle" "actual: ${haystack:0:200}" ;;
  esac
}

summary() {
  printf '\n'
  if [ "$TESTS_FAILED" -eq 0 ]; then
    printf '%s%d passed%s\n' "$GREEN" "$TESTS_RUN" "$RESET"
    return 0
  fi
  printf '%s%d of %d failed%s\n' "$RED" "$TESTS_FAILED" "$TESTS_RUN" "$RESET"
  return 1
}

# ── Hook helpers ─────────────────────────────────────────────────────────────

# payload <tool_name> <command-or-path>  → the JSON Claude Code sends a hook
payload() {
  python3 -c '
import json, sys
tool, val = sys.argv[1], sys.argv[2]
key = "command" if tool == "Bash" else "file_path"
print(json.dumps({"tool_name": tool, "tool_input": {key: val}}))
' "$1" "$2"
}

# run_standalone <hook-file> <tool_name> <value>
# Invokes the hook the way Claude Code does: JSON on stdin, exit code out.
# Sets $OUT and returns the hook's exit code.
#
# Note for callers: do NOT wrap these in $( ). They communicate via the global
# $OUT precisely so the exit code survives — a command substitution would run
# them in a subshell and discard it.
run_standalone() {
  local hook="$1" tool="$2" val="$3"
  OUT=$(payload "$tool" "$val" | bash "$hook" 2>&1)
  return $?
}

# run_suite <hook-file> <gate-fn> <tool_name> <value>
# Invokes the same gate the way enforce-suite.sh does: sourced with SUITE_MODE=1
# and pre-parsed variables. Sets $OUT and returns the gate's exit code.
run_suite() {
  local hook="$1" fn="$2" tool="$3" val="$4" repo
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  OUT=$(
    payload "$tool" "$val" | SUITE_MODE=1 bash -c '
      . "$3/hooks/aether-config.sh"
      # Exactly what enforce-suite.sh does before it dispatches: one parse, which
      # sets tool_name, cmd_or_path and the AETHER_* the gates read. Setting those
      # by hand here would have made the equivalence assertion vacuous — the whole
      # point is that both modes go through this same function.
      aether_parse_command "$(cat)"
      . "$1"
      "$2"
    ' _ "$hook" "$fn" "$repo" 2>&1
  )
  return $?
}

# assert_dual_mode <hook> <gate-fn> <tool> <value> <label>
# The core Phase 5 guarantee: a gate must behave identically whether the plugin
# hook runs standalone or is sourced by the suite dispatcher.
assert_dual_mode() {
  local hook="$1" fn="$2" tool="$3" val="$4" label="$5"
  local so su se ue
  run_standalone "$hook" "$tool" "$val"; se=$?; so="$OUT"
  run_suite "$hook" "$fn" "$tool" "$val"; ue=$?; su="$OUT"
  # Identical output, and the same verdict — but not necessarily the same number.
  # A gate returns 2 for a block and 1 for a nudge so the dispatcher's budget can
  # tell them apart; standalone, the entrypoint clamps both to 1 because the hook
  # contract is exit 0 or 1 and never 2. assert_severity pins the distinction the
  # clamp erases.
  local sv uv
  sv=$([ "$se" -eq 0 ] && echo silent || echo speaks)
  uv=$([ "$ue" -eq 0 ] && echo silent || echo speaks)
  if [ "$so" = "$su" ] && [ "$sv" = "$uv" ]; then
    pass "$label ($sv, identical in both modes)"
  else
    fail "$label" \
      "standalone: exit=$se output=${so:0:90}" \
      "suite:      exit=$ue output=${su:0:90}"
  fi
}

# assert_severity <hook> <gate-fn> <tool> <value> <expected-rc> <label>
# The gate's return code in suite mode: 0 silent, 1 nudge, 2 block. The budget in
# enforce-suite.sh suppresses nudges and never suppresses blocks, so a gate that
# returns the wrong number is a guardrail that silently stops guarding.
assert_severity() {
  local hook="$1" fn="$2" tool="$3" val="$4" want="$5" label="$6" got
  run_suite "$hook" "$fn" "$tool" "$val"; got=$?
  if [ "$got" -eq "$want" ]; then
    pass "$label (rc=$got)"
  else
    fail "$label" "expected rc=$want, got rc=$got"
  fi
}
