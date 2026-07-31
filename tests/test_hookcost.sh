#!/usr/bin/env bash
# tests/test_hookcost.sh — what the hook costs, and what it can be talked out of.
#
# The PreToolUse hook runs on every Bash, Write, Edit and MultiEdit call of every
# session, so its cost is paid constantly and its bypass is the only thing standing
# between a guardrail and a habit of switching it off. Three properties are asserted
# here that nothing else covers:
#
#   1. **One interpreter per tool call.** A `git commit` used to start three python3
#      processes — the dispatcher's stdin parse, temper's rule and cairn's rule — at
#      roughly 18ms each. Counted rather than timed, because a loaded CI machine can
#      make any timing assertion flap, and because the count is the thing that was
#      actually wrong.
#
#   2. **Bypass precision.** Every gate used to grep for its marker anywhere in the
#      command, so `git commit -m "docs: explain # aether:skip"` silenced the whole
#      suite. The marker is now only honoured in a trailing comment. Each row below
#      was checked against the old code first; the mid-string ones bypassed there.
#
#   3. **The budget, and its one exemption.** One nudge per tool call — but never at
#      the cost of a block.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

SUITE_HOOK="$REPO/hooks/enforce-suite.sh"

FIX=$(mktemp -d)
export HOME="$FIX/home"
mkdir -p "$HOME"
cd "$FIX" || exit 1
git init -q . >/dev/null 2>&1
git config user.email t@t
git config user.name t
printf 'x\n' > file.txt
git add file.txt
git commit -qm init >/dev/null 2>&1

run_hook() {
  OUT=$(payload "$1" "$2" | bash "$SUITE_HOOK" 2>&1)
  return $?
}

# ── 1. one interpreter per tool call ─────────────────────────────────────────
# bash -x traces every command the hook runs, including the ones inside $( ).
suite "interpreter count"

interpreters() {
  payload "$1" "$2" | bash -x "$SUITE_HOOK" 2>&1 >/dev/null \
    | grep -c '^+* *python3' || true
}

assert_max_one() {
  local tool="$1" val="$2" label="$3" n
  n=$(interpreters "$tool" "$val")
  if [ "$n" -le 1 ]; then
    pass "$label ($n python3)"
  else
    fail "$label" "$n python3 starts — a rule has moved back into an interpreter"
  fi
}

# The worst case first: a commit large enough to trip temper and weak enough to
# trip cairn, on a repo with an uncritiqued plan, so all four gates have work.
mkdir -p .claude/plans .aether
printf '# A plan\n\nDo the thing.\n' > .claude/plans/p.md
i=0; : > big.txt
while [ "$i" -lt 250 ]; do printf 'l\n' >> big.txt; i=$((i + 1)); done
printf 'x\n' > auth.py
git add -A >/dev/null 2>&1

assert_max_one Bash  'git commit -m wip'          "git commit, all four gates with something to say"
assert_max_one Bash  'git push origin main'       "git push"
assert_max_one Bash  'grep -r foo src/app.py'     "grep on a source file"
assert_max_one Bash  'ls -la'                     "a command no gate cares about"
assert_max_one Write 'src/app.py'                 "Write to a source file"
assert_max_one Write 'README.md'                  "Write to a non-source file"

git reset -q >/dev/null 2>&1; rm -f big.txt auth.py

# ── 2. bypass precision ──────────────────────────────────────────────────────
suite "bypass precision"

# bypassed <plugin> <command>  → "yes" | "no"
bypassed() {
  payload Bash "$2" | bash -c '
    . "$1/hooks/aether-config.sh"
    aether_parse_command "$(cat)" >/dev/null 2>&1 || exit 0
    aether_bypassed "$2" && echo yes || echo no
  ' _ "$REPO" "$1"
}

assert_bypass() {
  local want="$1" plugin="$2" cmd="$3" label="$4" got
  got=$(bypassed "$plugin" "$cmd")
  assert_eq "$want" "$got" "$label"
}

assert_bypass yes temper 'git commit -m wip # temper:skip'    'a trailing marker bypasses'
assert_bypass yes temper 'git commit -m wip #temper:skip'     'no space after # is still a comment'
assert_bypass yes temper 'git commit -m wip #  temper:skip'   'extra space is fine'
assert_bypass yes temper 'git commit -m wip # aether:skip'    'aether:skip covers every plugin'
assert_bypass yes temper 'git commit -m wip # suite:skip'     'suite:skip is its alias'
assert_bypass yes cairn  'git commit -m wip # temper:skip cairn:skip' 'two markers, both honoured'

# Each of these silenced the suite before the marker had to be a trailing comment.
assert_bypass no  temper 'git commit -m "docs: # temper:skip"'  'inside a double-quoted message: not a comment'
assert_bypass no  temper "git commit -m 'docs: # temper:skip'"  'inside a single-quoted message: not a comment'
assert_bypass no  temper 'git commit -m wip # temper:skip && rm -rf /' 'a marker mid-comment is not trailing'
assert_bypass no  bonsai 'echo hi # bonsai:skip is how you skip'      'prose after the marker is not a bypass'
assert_bypass no  temper 'git commit -m wip # TEMPER:skip'      'the marker is case-sensitive'
assert_bypass no  temper 'git commit -m "temper:skip"'          'no # at all is not a bypass'
assert_bypass no  cairn  'git commit -m wip # temper:skip'      'one plugin marker does not silence another'
assert_bypass no  temper 'git commit -m wip'                    'no marker, no bypass'

# The same string, the same answer, everywhere. Three files used to spell the
# whitespace three different ways.
suite "every gate agrees on the marker"
for c in 'git push origin main # temper:skip' \
         'git push origin main # aether:skip' \
         'git push origin main'; do
  first=""
  same=yes
  for plugin in whetstone bonsai temper cairn; do
    v=$(bypassed "$plugin" "${c/temper:skip/$plugin:skip}")
    [ -z "$first" ] && first="$v"
    [ "$v" = "$first" ] || same=no
  done
  assert_eq yes "$same" "all four gates agree on: ${c##*# }"
done

# ── 3. the budget and its exemption ──────────────────────────────────────────
suite "the budget"

i=0; : > big.txt
while [ "$i" -lt 250 ]; do printf 'l\n' >> big.txt; i=$((i + 1)); done
git add -A >/dev/null 2>&1

run_hook Bash 'git commit -m wip'
n=$(printf '%s\n' "$OUT" | grep -c . || true)
if [ "$n" -le 6 ]; then
  pass "one commit is $n lines (three plugins used to print 15)"
else
  fail "the budget holds the output down" "$n lines"
fi
assert_contains "$OUT" "Whetstone" "the earliest stage in the lifecycle prints"
assert_contains "$OUT" "also had notes" "the rest are one line, not three nudges"

suite "a block is never budgeted"
run_hook Bash 'git push origin main'; e=$?
assert_exit 1 "$e" "an unreviewed push still exits non-zero"
assert_contains "$OUT" "temper: about to push" "the block prints in full"
case "$OUT" in
  *"also had notes"*) fail "a block prints alone" "the summary line appeared beside a block" ;;
  *) pass "a block prints alone" ;;
esac
case "$OUT" in
  *Whetstone*|*"Cairn nudge"*) fail "the nudges beside a block are dropped" "a nudge printed anyway" ;;
  *) pass "the nudges beside a block are dropped" ;;
esac
# Dropped from the output, not lost: nothing announced them, so --notes is the
# only way to find them.
assert_contains "$("$REPO/bin/aether" status --notes 2>&1)" "Whetstone" \
  "…but recorded, since nothing announced them"

# ── 4. the notes file belongs to the project ─────────────────────────────────
# Third time this rule has had to be rediscovered: the v1.1.0 nudge sentinel and
# the v1.4.0 plan pointer both resolved through aether_out_dir, whose ~/.aether/out
# fallback let one project's state surface in another.
suite "the notes file is project-relative"
if [ -e "$HOME/.aether/out/.notes" ]; then
  fail "never lands in HOME" "found $HOME/.aether/out/.notes"
else
  pass "never lands in HOME"
fi
assert_eq ".aether/out/.notes" \
  "$(bash -c '. "$1/hooks/aether-config.sh"; aether_notes_file' _ "$REPO")" \
  "resolves inside the project"

NOAE=$(mktemp -d); cd "$NOAE" || exit 1
assert_eq "" "$(bash -c '. "$1/hooks/aether-config.sh"; aether_notes_file' _ "$REPO")" \
  "resolves to nothing when the project has no .aether/"
cd "$FIX" || exit 1
rm -rf "$NOAE"

cd /
rm -rf "$FIX"
summary
