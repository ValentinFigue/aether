#!/usr/bin/env bash
# tests/test_rules.sh — what each gate's rule actually decides.
#
# In v1.5.0 cairn's, temper's and bonsai's rules moved out of python and into bash,
# git and awk, to get the hook down to one interpreter per tool call. Before the old
# implementations were removed, each new one was diffed against them over the inputs
# below — 35 commit messages, all five of temper's branches at and around every
# threshold, 26 bonsai commands — and all three were byte-identical.
#
# That diff is not repeatable now: the python is gone. These are the same inputs kept
# as assertions, so the behaviour the port preserved stays preserved. Every row here
# was chosen because it distinguishes something — a boundary, a precedence, a case
# where two plausible readings of the rule disagree.
#
# tests/test_gates.sh covers the surrounding contract (dual-mode equivalence, bypass,
# fail-open, severity). This file covers the decisions.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

CAIRN="$REPO/plugins/cairn/hooks/enforce-cairn.sh"
TEMPER="$REPO/plugins/temper/hooks/enforce-temper.sh"
BONSAI="$REPO/plugins/bonsai/hooks/enforce-bonsai.sh"

FIX=$(mktemp -d)
export HOME="$FIX/home"
mkdir -p "$HOME"

# verdict <gate> <command>  → the first word of the nudge, or "" when silent
verdict() {
  payload Bash "$2" | bash "$1" 2>&1 | head -1 | cut -d' ' -f1-3
}

# rule <gate> <expected> <command> — expected is a substring, or "" for silence
rule() {
  local gate="$1" want="$2" cmd="$3" got
  got=$(verdict "$gate" "$cmd")
  if [ -z "$want" ]; then
    if [ -z "$got" ]; then pass "silent: $cmd"
    else fail "silent: $cmd" "got: $got"; fi
  else
    case "$got" in
      *"$want"*) pass "$want: $cmd" ;;
      *) fail "$want: $cmd" "got: ${got:-<silent>}" ;;
    esac
  fi
}

# ── cairn: what makes a commit message weak ──────────────────────────────────
suite "cairn — weak messages"
for m in wip fix update refactor cleanup tmp ok more; do
  rule "$CAIRN" "Cairn nudge" "git commit -m $m"
done
rule "$CAIRN" "Cairn nudge" 'git commit -m "more changes"'
rule "$CAIRN" "Cairn nudge" 'git commit -m "minor tweak"'
rule "$CAIRN" "Cairn nudge" 'git commit -m "fixed bug"'
rule "$CAIRN" "Cairn nudge" 'git commit -m "adding things"'
rule "$CAIRN" "Cairn nudge" 'git commit -m "Adds it"'
rule "$CAIRN" "Cairn nudge" 'git commit -m "WIP"'
rule "$CAIRN" "Cairn nudge" 'git commit -m "Wip."'          # rstrip(".,!") before the lookup
# Not weak: 23 characters, no weak word on its own, no weak pattern. The single
# quotes are the point — the extraction has to see through them to judge at all.
rule "$CAIRN" "" "git commit -m 'single quoted weak wip'"

suite "cairn — the conventional-commit escape hatch"
# Checked before weakness, so `fix:` outranks "fix" being a weak word — but only
# with a description of ten characters or more.
rule "$CAIRN" "" 'git commit -m "feat: add rate limiting to the API"'
rule "$CAIRN" "" 'git commit -m "fix(auth)!: correct the token check"'
rule "$CAIRN" "" 'git commit -m "chore: bump dependency versions for security"'
rule "$CAIRN" "Cairn nudge" 'git commit -m "feat: short"'   # 5 chars — under the floor
rule "$CAIRN" "" 'git commit -m "a message that is quite long and descriptive enough"'

suite "cairn — message extraction"
rule "$CAIRN" "Cairn nudge" 'git commit'                     # no -m at all
rule "$CAIRN" "Cairn nudge" 'git commit -a'
rule "$CAIRN" "Cairn nudge" 'git commit -am "wip"'
rule "$CAIRN" "Cairn nudge" 'git commit --message "wip"'
rule "$CAIRN" "Cairn nudge" 'git commit --message="wip"'
rule "$CAIRN" "Cairn nudge" 'git commit -m "   "'            # strips to empty, still weak

suite "cairn — push, and things that are not git"
rule "$CAIRN" "Cairn nudge" 'git push'
rule "$CAIRN" "Cairn nudge" 'git push origin main'
rule "$CAIRN" "" 'git push --dry-run'
rule "$CAIRN" "" 'git push -n'
rule "$CAIRN" "" 'git status'
# cairn searches the whole command for git…commit, so a command that merely quotes
# one trips it. temper anchors at position 0 and does not. Both behaviours predate
# v1.5.0 and are asserted rather than reconciled — see the temper branch rows below.
rule "$CAIRN" "Cairn nudge" 'echo "git commit -m wip"'

# ── temper: thresholds and paths ─────────────────────────────────────────────
suite "temper — branches"
TW="$FIX/repo"; mkdir -p "$TW"; cd "$TW" || exit 1
git init -q -b main . >/dev/null 2>&1
git config user.email t@t; git config user.name t
printf 'seed\n' > seed.txt; git add -A; git commit -qm seed
i=1; while [ "$i" -le 7 ]; do printf 'c\n' > "f$i.txt"; git add -A; git commit -qm "c$i"; i=$((i + 1)); done

rule "$TEMPER" "temper:" 'git push'
rule "$TEMPER" "" 'git push --dry-run'
rule "$TEMPER" "" 'git push -n'
# temper anchors on `git` at position 0 where cairn does not. Asserted rather than
# fixed: reconciling them is a behaviour change, not a port.
rule "$TEMPER" "" 'echo hi && git push'
rule "$TEMPER" "temper:" 'git merge main'
rule "$TEMPER" "" 'git merge feature'
rule "$TEMPER" "" 'git merge'
rule "$TEMPER" "temper:" 'git rebase -i HEAD~9'
rule "$TEMPER" "" 'git rebase -i HEAD~3'
rule "$TEMPER" "" 'git rebase -i'
rule "$TEMPER" "" 'git rebase HEAD~9'

suite "temper — commit thresholds"
stage() { git reset -q; git checkout -q -- . 2>/dev/null; rm -f big.txt m*.txt auth.py schema.sql .env x.py 2>/dev/null; }
stage; printf 'one\n' > x.py; git add -A
rule "$TEMPER" "" 'git commit -m x'
stage; i=0; : > big.txt; while [ "$i" -lt 200 ]; do printf 'l\n' >> big.txt; i=$((i + 1)); done; git add -A
rule "$TEMPER" "" 'git commit -m x'                          # exactly at the threshold: not over
stage; i=0; : > big.txt; while [ "$i" -lt 201 ]; do printf 'l\n' >> big.txt; i=$((i + 1)); done; git add -A
rule "$TEMPER" "temper:" 'git commit -m x'                   # one line over
stage; i=1; while [ "$i" -le 10 ]; do printf 'a\n' > "m$i.txt"; i=$((i + 1)); done; git add -A
rule "$TEMPER" "" 'git commit -m x'                          # exactly ten files
stage; i=1; while [ "$i" -le 11 ]; do printf 'a\n' > "m$i.txt"; i=$((i + 1)); done; git add -A
rule "$TEMPER" "temper:" 'git commit -m x'                   # one file over

suite "temper — critical paths"
for f in auth.py schema.sql .env AUTH.PY; do
  stage; printf 'a\n' > "$f"; git add -A
  rule "$TEMPER" "temper:" "git commit -m x"   # $f — including the case-insensitive one
done
stage

suite "temper — stash"
i=0; : > big.txt; while [ "$i" -lt 250 ]; do printf 'l\n' >> big.txt; i=$((i + 1)); done
git add -A; git stash -q
rule "$TEMPER" "temper:" 'git stash pop'
git stash drop -q 2>/dev/null
printf 'two\n' >> seed.txt; git stash -q
rule "$TEMPER" "" 'git stash pop'
git stash drop -q 2>/dev/null
cd "$FIX" || exit 1

# ── bonsai: which tool on which file ─────────────────────────────────────────
suite "bonsai — categories"
rule "$BONSAI" "Bonsai nudge" 'grep -r foo src/app.py'
rule "$BONSAI" "Bonsai nudge" 'rg symbol lib/x.tsx'
rule "$BONSAI" "Bonsai nudge" 'ag thing a.jsx'
rule "$BONSAI" "Bonsai nudge" 'ack thing a.mjs'
rule "$BONSAI" "Bonsai nudge" 'fgrep x a.js'
rule "$BONSAI" "Bonsai nudge" 'sed -i s/a/b/ src/app.py'
rule "$BONSAI" "Bonsai nudge" "awk '{print}' src/app.py"
rule "$BONSAI" "Bonsai nudge" 'perl -pi -e s/a/b/ src/app.ts'
rule "$BONSAI" "Bonsai nudge" 'mv old.py new.py'
rule "$BONSAI" "Bonsai nudge" 'git mv old.ts new.ts'
rule "$BONSAI" "Bonsai nudge" 'cp a.js b.js'
rule "$BONSAI" "Bonsai nudge" "find . -name '*.py' | xargs sed -i s/a/b/"

suite "bonsai — silence"
rule "$BONSAI" "" 'grep -r foo README.md'
rule "$BONSAI" "" 'sed -i s/a/b/ config.yaml'
rule "$BONSAI" "" 'mv docs/a.md docs/b.md'
rule "$BONSAI" "" 'echo app.py'                # no matching tool
rule "$BONSAI" "" 'cat src/app.py'             # reading is not searching
rule "$BONSAI" "" 'grep foo app.pyx'           # .py must end the word
rule "$BONSAI" "" 'grep foo notes.python'
rule "$BONSAI" "" 'find . | xargs perl -pi -e x'   # no source file named

suite "bonsai — precedence"
# move outranks search, mutate outranks search — the first category that matches wins.
rule "$BONSAI" "Bonsai nudge" 'mv a.py b.py && grep x c.ts'
rule "$BONSAI" "Bonsai nudge" 'grep x a.ts | sed s/a/b/'
mv_out=$(payload Bash 'mv a.py b.py && grep x c.ts' | bash "$BONSAI" 2>&1)
assert_contains "$mv_out" "moving or copying" "move outranks search"
sed_out=$(payload Bash 'grep x a.ts | sed s/a/b/' | bash "$BONSAI" 2>&1)
assert_contains "$sed_out" "mutating" "mutate outranks search"

cd /
rm -rf "$FIX"
summary
