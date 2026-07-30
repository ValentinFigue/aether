#!/usr/bin/env bash
# tests/test_gates.sh — the four PreToolUse gates.
#
# The headline guarantee is dual-mode equivalence: after Phase 5 each gate has
# exactly one definition, invoked either directly (plugin standalone) or by
# sourcing into enforce-suite.sh. These tests prove both paths agree, which is
# what makes deleting the suite's ~400 lines of copied gate logic safe.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

BONSAI="$REPO/plugins/bonsai/hooks/enforce-bonsai.sh"
CAIRN="$REPO/plugins/cairn/hooks/enforce-cairn.sh"
WHET="$REPO/plugins/whetstone/hooks/enforce-whetstone.sh"
TEMPER="$REPO/plugins/temper/hooks/enforce-temper.sh"

# ── Every hook must at least parse ───────────────────────────────────────────
# enforce-cairn.sh shipped for months with a syntax error that only surfaced at
# runtime, as a bash parse error in place of the nudge. Cheap guard against a
# repeat.
suite "shell syntax"
for h in "$BONSAI" "$CAIRN" "$WHET" "$TEMPER" "$REPO/hooks/enforce-suite.sh"; do
  if bash -n "$h" 2>/dev/null; then
    pass "parses: ${h#$REPO/}"
  else
    fail "parses: ${h#$REPO/}" "$(bash -n "$h" 2>&1 | head -2)"
  fi
done

# ── cairn ────────────────────────────────────────────────────────────────────
suite "cairn gate"
assert_dual_mode "$CAIRN" gate_cairn Bash 'git commit -m wip'                    "weak message nudges"
assert_dual_mode "$CAIRN" gate_cairn Bash 'git commit'                           "missing -m nudges"
assert_dual_mode "$CAIRN" gate_cairn Bash 'git push origin main'                 "push nudges"
assert_dual_mode "$CAIRN" gate_cairn Bash 'git push --dry-run'                   "dry-run push is silent"
assert_dual_mode "$CAIRN" gate_cairn Bash 'git commit -m "feat(x): a real conventional message"' "conventional commit is silent"
assert_dual_mode "$CAIRN" gate_cairn Bash 'ls -la'                               "unrelated command is silent"
assert_dual_mode "$CAIRN" gate_cairn Bash "git commit -m 'single quoted message here'" "single-quoted message parses"

run_standalone "$CAIRN" Bash 'git commit -m wip'; e=$?; out="$OUT"
assert_exit 1 "$e" "cairn: weak message exits 1"
assert_contains "$out" "Cairn nudge" "cairn: prints the nudge, not a bash error"
case "$out" in
  *"syntax error"*) fail "cairn: no bash syntax error in output" "got: ${out:0:120}" ;;
  *) pass "cairn: no bash syntax error in output" ;;
esac

# ── bonsai ───────────────────────────────────────────────────────────────────
suite "bonsai gate"
assert_dual_mode "$BONSAI" gate_bonsai Bash 'grep -r foo src/app.py'       "grep on .py nudges"
assert_dual_mode "$BONSAI" gate_bonsai Bash 'sed -i s/a/b/ src/app.py'     "sed on .py nudges"
assert_dual_mode "$BONSAI" gate_bonsai Bash 'mv src/a.ts src/b.ts'         "mv on .ts nudges"
assert_dual_mode "$BONSAI" gate_bonsai Bash 'grep -r foo README.md'        "grep on .md is silent"
assert_dual_mode "$BONSAI" gate_bonsai Bash 'echo hello'                   "unrelated command is silent"

# ── whetstone ────────────────────────────────────────────────────────────────
# Runs inside a fixture directory so .claude/plans state is deterministic.
suite "whetstone gate"
WS_FIX=$(mktemp -d)
mkdir -p "$WS_FIX/.claude/plans"
: > "$WS_FIX/.claude/plans/some-plan.md"
# cd rather than subshell so each assertion reports individually and the
# pass/fail counters stay in this shell.
cd "$WS_FIX" || exit 1
assert_dual_mode "$WHET" gate_whetstone Bash 'git commit -m x' "plan without critique nudges"
assert_dual_mode "$WHET" gate_whetstone Write 'notes.md'       "non-source write is silent"

# The Write gate is stateful — it nudges once per project and drops a sentinel.
# assert_dual_mode runs standalone first, which would leave the sentinel behind
# and make the suite run legitimately silent, so it is reset between the modes.
#
# Project-relative on purpose: it is a once-per-project nudge, so it must not
# route through aether_out_dir, which falls back to ~/.aether/out for a project
# that has no .aether/ — one nudged project would then silence the whole machine.
SENTINEL=".aether/out/.nudged"
rm -f "$SENTINEL"; run_standalone "$WHET" Write 'src/new.py';               ws_se=$?; ws_so="$OUT"
rm -f "$SENTINEL"; run_suite "$WHET" gate_whetstone Write 'src/new.py';     ws_ue=$?; ws_su="$OUT"
if [ "$ws_so" = "$ws_su" ] && [ "$ws_se" -eq "$ws_ue" ]; then
  pass "source write without critique nudges (exit $ws_se, identical in both modes)"
else
  fail "source write without critique nudges" \
    "standalone: exit=$ws_se output=${ws_so:0:90}" \
    "suite:      exit=$ws_ue output=${ws_su:0:90}"
fi

# whetstone's Write gate nudges once per project, guarded by a sentinel file
rm -f "$WS_FIX/$SENTINEL"
run_standalone "$WHET" Write 'src/a.py'; first=$?
run_standalone "$WHET" Write 'src/b.py'; second=$?
assert_exit 1 "$first"  "whetstone: first source write nudges"
assert_exit 0 "$second" "whetstone: second source write is silent (sentinel honoured)"

# Regression: the sentinel moved to .aether/out/ and briefly resolved through
# aether_out_dir, which falls back to ~/.aether/out. One nudged project then
# silenced every other project on the machine.
WS_FIX2=$(mktemp -d)
mkdir -p "$WS_FIX2/.claude/plans"; : > "$WS_FIX2/.claude/plans/some-plan.md"
cd "$WS_FIX2" || exit 1
run_standalone "$WHET" Write 'src/c.py'; other=$?
assert_exit 1 "$other" "whetstone: a second project is still nudged (sentinel is per-project)"
cd "$WS_FIX" || exit 1

# with a critique newer than the plan, nothing should fire
: > "$WS_FIX/.claude/plans/CRITIQUE.md"
run_standalone "$WHET" Bash 'git commit -m x'; e=$?
assert_exit 0 "$e" "whetstone: fresh critique silences the commit gate"

cd "$REPO" || exit 1
rm -rf "$WS_FIX"

# ── temper ───────────────────────────────────────────────────────────────────
# Fixture git repo so staged-diff size is deterministic.
suite "temper gate"
TP_FIX=$(mktemp -d)
cd "$TP_FIX" || exit 1
git init -q .
git config user.email t@t
git config user.name t
printf 'x\n' > file.txt
git add file.txt
git commit -qm init

assert_dual_mode "$TEMPER" gate_temper Bash 'git push origin main'   "push nudges"
assert_dual_mode "$TEMPER" gate_temper Bash 'git push --dry-run'     "dry-run push is silent"
assert_dual_mode "$TEMPER" gate_temper Bash 'git commit -m x'        "small commit is silent"
assert_dual_mode "$TEMPER" gate_temper Bash 'git merge main'         "merge to primary nudges"
assert_dual_mode "$TEMPER" gate_temper Bash 'git merge feature-xyz'  "merge to non-primary is silent"
assert_dual_mode "$TEMPER" gate_temper Bash 'echo hi'                "unrelated command is silent"

# a critical-path file in the staged diff must trip the commit gate
printf 'secret\n' > auth_token.py
git add auth_token.py
run_standalone "$TEMPER" Bash 'git commit -m x'; e=$?; out="$OUT"
assert_exit 1 "$e" "temper: staged critical-path file nudges"
assert_contains "$out" "critical path" "temper: names the critical-path reason"

# enabled:false in temper.config must silence it entirely
printf 'enabled: false\n' > temper.config
run_standalone "$TEMPER" Bash 'git push origin main'; e=$?
assert_exit 0 "$e" "temper: enabled:false silences the gate"
rm -f temper.config

cd "$REPO" || exit 1

# temper used to mktemp a python file on every invocation; it now inlines the
# heredoc, so nothing should accumulate in /tmp.
before=$(find /tmp -maxdepth 1 -name 'temper_check.*' 2>/dev/null | wc -l | tr -d ' ')
run_standalone "$TEMPER" Bash 'git push origin main' >/dev/null 2>&1
after=$(find /tmp -maxdepth 1 -name 'temper_check.*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$before" "$after" "temper: leaves no temp files in /tmp"
rm -rf "$TP_FIX"

# ── bypass markers ───────────────────────────────────────────────────────────
suite "bypass markers"
# aether:skip is resolved by enforce-suite.sh, not by the plugin gates, so only
# the plugin's own marker and the shared suite marker are tested here.
for spec in "$CAIRN:gate_cairn:cairn" "$BONSAI:gate_bonsai:bonsai" "$TEMPER:gate_temper:temper"; do
  hook="${spec%%:*}"; rest="${spec#*:}"; fn="${rest%%:*}"; name="${rest#*:}"
  for marker in "$name" suite; do
    run_standalone "$hook" Bash "git push origin main # ${marker}:skip"; e=$?
    assert_exit 0 "$e" "$name: # ${marker}:skip silences the gate"
  done
done

# ── fail-open ────────────────────────────────────────────────────────────────
# A gate that cannot classify must never block the tool call.
suite "fail-open"
for spec in "$CAIRN:gate_cairn" "$BONSAI:gate_bonsai" "$TEMPER:gate_temper"; do
  hook="${spec%%:*}"; fn="${spec#*:}"
  out=$(printf 'not json at all' | bash "$hook" 2>&1); e=$?
  assert_exit 0 "$e" "${fn}: malformed stdin exits 0"
  out=$(printf '' | bash "$hook" 2>&1); e=$?
  assert_exit 0 "$e" "${fn}: empty stdin exits 0"
done

# ── sourcing must not leak shell options ─────────────────────────────────────
# The gates set -euo pipefail only inside their standalone entrypoint. If that
# leaked, enforce-suite.sh's fail-open wrapper would stop working.
suite "sourcing hygiene"
for spec in "$CAIRN:gate_cairn" "$BONSAI:gate_bonsai" "$WHET:gate_whetstone" "$TEMPER:gate_temper"; do
  hook="${spec%%:*}"; fn="${spec#*:}"
  opts=$(SUITE_MODE=1 bash -c '. "$1" >/dev/null 2>&1; echo "$-"' _ "$hook")
  case "$opts" in
    *e*) fail "${fn}: sourcing does not enable -e" "shell flags after source: $opts" ;;
    *)   pass "${fn}: sourcing does not enable -e" ;;
  esac
done

summary
