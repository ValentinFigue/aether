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

# ── the nudge budget ─────────────────────────────────────────────────────────
# A single git push trips temper and cairn, and may trip whetstone too. Before
# the budget the dispatcher printed all of them — fifteen lines from three
# plugins on one commit, which is how a guardrail teaches people to bypass it.
#
# temper's push is a block, so it prints in full and alone: the nudges beside it
# are dropped rather than appended. Suppressing a block would turn "you cannot
# push unreviewed" into "you might not hear about it".
suite "the nudge budget"
run_hook Bash 'git push origin main'
assert_contains "$OUT" "temper:" "a block prints"
case "$OUT" in
  *"Cairn nudge"*) fail "a block suppresses the nudges beside it" "cairn's nudge printed alongside the block" ;;
  *) pass "a block suppresses the nudges beside it" ;;
esac

# A commit with no block: one nudge in full, then one line naming the rest.
: > big.txt; i=0; while [ "$i" -lt 250 ]; do printf 'l\n' >> big.txt; i=$((i + 1)); done
git add big.txt >/dev/null 2>&1
run_hook Bash 'git commit -m wip'
assert_contains "$OUT" "temper:"       "the earliest stage still to speak prints in full"
assert_contains "$OUT" "also had notes" "the rest are named on one line"
case "$OUT" in
  *"Cairn nudge"*) fail "only one nudge prints in full" "cairn's full nudge printed too" ;;
  *) pass "only one nudge prints in full" ;;
esac
assert_contains "$OUT" "cairn" "the summary line names who was held back"

# And what was held back outlives the hook, or "+ cairn also had notes" is a dead end.
# .aether/ is what makes the notes file project-relative: without one there is
# nowhere in *this* repo to put them, and writing to ~/.aether/out instead would
# let one project's nudges surface in another.
mkdir -p .aether
run_hook Bash 'git commit -m wip'
if [ -s .aether/out/.notes ]; then
  pass "suppressed nudges are recorded"
  assert_contains "$(cat .aether/out/.notes)" "Cairn nudge" "…in full, not just by name"
else
  fail "suppressed nudges are recorded" ".aether/out/.notes is missing or empty"
fi
assert_contains "$("$REPO/bin/aether" status --notes 2>&1)" \
  "Cairn nudge" "aether status --notes shows them"

# The other half of project-relative: it must never land in $HOME.
if [ -e "$HOME/.aether/out/.notes" ]; then
  fail "the notes file never lands in HOME" "found $HOME/.aether/out/.notes"
else
  pass "the notes file never lands in HOME"
fi
git reset -q >/dev/null 2>&1; rm -f big.txt

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

# ── a broken gate must not block the user ────────────────────────────────────
# This hook runs on every Bash, Write and Edit call. A gate file that is corrupt
# or half-written (interrupted install, full disk) used to make sourcing fail
# under `set -e`, aborting the hook with exit 2 — which Claude Code reads as
# "block the tool call". One bad file locked the user out of every command.
suite "broken gate degrades safely"
for kind in corrupt truncated empty; do
  BG=$(mktemp -d)
  for p in whetstone bonsai temper cairn; do
    cp "$REPO/plugins/$p/hooks/enforce-$p.sh" "$BG/enforce-$p.sh"
  done
  case "$kind" in
    corrupt)   printf 'gate_cairn() {\n  this is ( not valid bash\n' > "$BG/enforce-cairn.sh" ;;
    truncated) head -40 "$REPO/plugins/cairn/hooks/enforce-cairn.sh" > "$BG/enforce-cairn.sh" ;;
    empty)     : > "$BG/enforce-cairn.sh" ;;
  esac

  OUT=$(payload Bash 'git push origin main' | AETHER_GATE_DIR="$BG" bash "$SUITE_HOOK" 2>&1); e=$?
  if [ "$e" -le 1 ]; then
    pass "$kind gate: hook exits $e, never 2 (would block the tool call)"
  else
    fail "$kind gate: hook exits $e, never 2" "exit=$e output=${OUT:0:150}"
  fi
  case "$OUT" in
    *"syntax error"*|*"unexpected"*) fail "$kind gate: no bash noise reaches the user" "output=${OUT:0:150}" ;;
    *) pass "$kind gate: no bash noise reaches the user" ;;
  esac
  assert_contains "$OUT" "temper:" "$kind gate: the healthy gates still fire"
  rm -rf "$BG"
done

# aether status is the one place a broken gate is reported, since the hook
# itself has to stay silent.
BG=$(mktemp -d)
cp "$REPO/plugins/temper/hooks/enforce-temper.sh" "$BG/enforce-temper.sh"
printf 'not ( valid\n' > "$BG/enforce-cairn.sh"
H=$(mktemp -d)
mkdir -p "$H/.claude"
printf 'version=1.0.0\nscope=global\ngates=%s\n' "$BG" > "$H/.claude/aether.manifest"
out=$(env HOME="$H" bash "$REPO/bin/aether" status 2>&1)
assert_contains "$out" "failed to parse" "aether status reports the unparseable gate"
assert_contains "$out" "enforce-cairn.sh" "aether status names the bad gate"
rm -rf "$BG" "$H"

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
# Code lines, not total lines: the budget arrived with a long explanation of why
# a block is exempt, and a rule that counts comments punishes writing it down.
lines=$(grep -cvE '^[[:space:]]*(#|$)' "$SUITE_HOOK")
if [ "$lines" -lt 150 ]; then
  pass "dispatcher stayed small ($lines code lines, was 300+ when it carried the gates)"
else
  fail "dispatcher stayed small" "$lines code lines — gate logic may have crept back in"
fi

cd "$REPO" || exit 1
rm -rf "$FIX"

summary
