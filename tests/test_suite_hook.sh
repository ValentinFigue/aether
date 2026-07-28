#!/usr/bin/env bash
# tests/test_suite_hook.sh — the enforce-suite.sh dispatcher.
#
# enforce-suite.sh no longer contains any gate logic; it resolves each gate from
# the owning plugin, applies bypass and enabled checks, and accumulates exit
# codes. These tests cover the dispatcher's own responsibilities.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

SUITE_HOOK="$REPO/hooks/enforce-suite.sh"

# run_hook <tool> <value>  — sets $OUT, returns the hook's exit code
run_hook() {
  OUT=$(payload "$1" "$2" | bash "$SUITE_HOOK" 2>&1)
  return $?
}

# A fixture git repo with no .claude/plans, so whetstone stays quiet and the
# other gates can be observed in isolation.
FIX=$(mktemp -d)
cd "$FIX" || exit 1
git init -q .
git config user.email t@t
git config user.name t
printf 'x\n' > file.txt
git add file.txt
git commit -qm init

# ── gates actually load ──────────────────────────────────────────────────────
suite "gate loading"
run_hook Bash 'git commit -m wip'; e=$?
assert_exit 1 "$e" "cairn gate reached through the dispatcher"
assert_contains "$OUT" "Cairn nudge" "cairn's message comes from the plugin, not a suite copy"

run_hook Bash 'grep -r foo src/app.py'; e=$?
assert_exit 1 "$e" "bonsai gate reached through the dispatcher"
assert_contains "$OUT" "Bonsai nudge" "bonsai's message comes from the plugin"

run_hook Bash 'git push origin main'; e=$?
assert_exit 1 "$e" "temper gate reached through the dispatcher"
assert_contains "$OUT" "temper:" "temper's message comes from the plugin"

# ── accumulation ─────────────────────────────────────────────────────────────
# A single git push trips both temper and cairn; the dispatcher must show both
# rather than stopping at the first.
suite "accumulation"
run_hook Bash 'git push origin main'
assert_contains "$OUT" "temper:"     "push surfaces the temper nudge"
assert_contains "$OUT" "Cairn nudge" "push surfaces the cairn nudge too"

# ── suite-wide bypass ────────────────────────────────────────────────────────
suite "suite-wide bypass"
for marker in aether suite; do
  run_hook Bash "git push origin main # ${marker}:skip"; e=$?
  assert_exit 0 "$e" "# ${marker}:skip silences every gate"
  assert_eq "" "$OUT" "# ${marker}:skip produces no output"
done

# ── per-plugin bypass is isolated ────────────────────────────────────────────
# Silencing cairn must not silence temper — the whole point of separate markers.
suite "per-plugin bypass"
run_hook Bash 'git push origin main # cairn:skip'; e=$?
assert_exit 1 "$e" "# cairn:skip leaves other gates active"
assert_contains "$OUT" "temper:" "# cairn:skip keeps temper firing"
case "$OUT" in
  *"Cairn nudge"*) fail "# cairn:skip suppresses the cairn nudge" "cairn still fired" ;;
  *) pass "# cairn:skip suppresses the cairn nudge" ;;
esac

run_hook Bash 'git push origin main # temper:skip'; e=$?
assert_contains "$OUT" "Cairn nudge" "# temper:skip keeps cairn firing"
case "$OUT" in
  *"temper:"*) fail "# temper:skip suppresses the temper nudge" "temper still fired" ;;
  *) pass "# temper:skip suppresses the temper nudge" ;;
esac

# ── <plugin>.config enabled:false ────────────────────────────────────────────
suite "enabled:false"
printf 'enabled: false\n' > cairn.config
run_hook Bash 'git push origin main'
case "$OUT" in
  *"Cairn nudge"*) fail "cairn.config enabled:false disables the cairn gate" "cairn still fired" ;;
  *) pass "cairn.config enabled:false disables the cairn gate" ;;
esac
assert_contains "$OUT" "temper:" "disabling cairn leaves temper enabled"
rm -f cairn.config

# ── fail-open ────────────────────────────────────────────────────────────────
suite "fail-open"
out=$(printf 'not json' | bash "$SUITE_HOOK" 2>&1); e=$?
assert_exit 0 "$e" "malformed stdin exits 0"
out=$(printf '' | bash "$SUITE_HOOK" 2>&1); e=$?
assert_exit 0 "$e" "empty stdin exits 0"
out=$(printf '{"tool_name":"Bash","tool_input":{}}' | bash "$SUITE_HOOK" 2>&1); e=$?
assert_exit 0 "$e" "missing command field exits 0"

# ── Write/Edit path ──────────────────────────────────────────────────────────
# Only whetstone inspects writes; bonsai/temper/cairn are Bash-only.
suite "Write/Edit dispatch"
mkdir -p .claude/plans
: > .claude/plans/a-plan.md
rm -f .claude/plans/.whetstone-nudged
run_hook Write 'src/new.py'; e=$?
assert_exit 1 "$e" "source write reaches whetstone's write path"
assert_contains "$OUT" "Whetstone" "whetstone's write message is shown"
run_hook Write 'src/new.py'; e=$?
assert_exit 0 "$e" "second write is silent (sentinel honoured)"
rm -rf .claude

# ── gate resolution ──────────────────────────────────────────────────────────
suite "gate resolution"
GATES=$(mktemp -d)
for p in whetstone bonsai temper cairn; do
  cp "$REPO/plugins/$p/hooks/enforce-$p.sh" "$GATES/enforce-$p.sh"
done
OUT=$(payload Bash 'git commit -m wip' | AETHER_GATE_DIR="$GATES" bash "$SUITE_HOOK" 2>&1); e=$?
assert_exit 1 "$e" "resolves gates from the installed gates/ directory"
assert_contains "$OUT" "Cairn nudge" "installed-layout gates produce the same nudge"

# With no gates anywhere the hook must stay silent rather than error.
EMPTY=$(mktemp -d)
OUT=$(payload Bash 'git commit -m wip' | AETHER_GATE_DIR="$EMPTY" bash "$SUITE_HOOK" 2>&1); e=$?
# The repo fallback still finds them when running from a checkout, so only the
# exit code is asserted here: never a crash.
case "$e" in
  0|1) pass "missing gates/ degrades without error (exit $e)" ;;
  *)   fail "missing gates/ degrades without error" "exit=$e output=${OUT:0:120}" ;;
esac
rm -rf "$GATES" "$EMPTY"

# ── no gate logic left in the dispatcher ─────────────────────────────────────
# Guards the Phase 5 invariant: if a rule reappears here, it has been duplicated
# again and the two copies will drift.
suite "no duplicated rules"
for needle in 'WEAK_SINGLE' 'pyfindrefs' 'auto_nudge_lines' 'Conventional Commits'; do
  if grep -q "$needle" "$SUITE_HOOK"; then
    fail "dispatcher does not re-implement '$needle'" "found in hooks/enforce-suite.sh"
  else
    pass "dispatcher does not re-implement '$needle'"
  fi
done
lines=$(wc -l < "$SUITE_HOOK" | tr -d ' ')
if [ "$lines" -lt 200 ]; then
  pass "dispatcher stayed small ($lines lines, was 467)"
else
  fail "dispatcher stayed small" "$lines lines — gate logic may have crept back in"
fi

cd "$REPO" || exit 1
rm -rf "$FIX"

summary
