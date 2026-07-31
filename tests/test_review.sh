#!/usr/bin/env bash
# tests/test_review.sh — `aether review`.
#
# "Has what I am about to push been reviewed?" — a question nothing could answer before
# this, which is why temper's push verdict fires unconditionally and is therefore useless
# as a gate. A check that always says no teaches people to ignore it.
#
# The design decision this file encodes: **hash the content, not the commit.** Recording
# a SHA breaks on the most ordinary flow there is — review the staged diff, commit it,
# and the SHA has moved while the content has not. The amend and rebase cases below are
# where that choice earns itself.
#
# The other property under test is that `unknown` is not a soft `no`. It means the
# question could not be answered, and nothing downstream may escalate on it — otherwise
# a machine without sha256, or a project without `.aether/`, gets a prompt it can never
# satisfy.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

CLI="$REPO/bin/aether"
WORK=()
cleanup() { for w in "${WORK[@]}"; do rm -rf "$w"; done; }
trap cleanup EXIT

# A scratch repo with an origin/main to push against.
repo() {
  local d; d=$(mktemp -d); WORK+=("$d")
  mkdir -p "$d/home" "$d/.aether"
  (
    cd "$d" || exit 1
    git init -q -b main . && git config user.email t@t && git config user.name t
    printf 'seed\n' > a.txt && git add -A && git commit -qm init
    git update-ref refs/remotes/origin/main HEAD
  ) >/dev/null 2>&1
  printf '%s' "$d"
}

rv()  { ( cd "$1" && env HOME="$1/home" AETHER_REPO="$REPO" bash "$CLI" review "${@:2}" 2>&1 ); }
st()  { rv "$1" status --raw; }
in_() { ( cd "$1" && shift && "$@" ) >/dev/null 2>&1; }

# ── the ordinary flow ────────────────────────────────────────────────────────
suite "review, commit, push"
D=$(repo)
assert_eq "reviewed" "$(st "$D")" "a branch level with its upstream has nothing unreviewed"
in_ "$D" sh -c 'printf "unreviewed\n" >> a.txt; git add -A; git commit -qm nope'
assert_eq "no" "$(st "$D")" "an unreviewed commit with nothing recorded reads as no"
in_ "$D" git reset -q --hard origin/main

in_ "$D" sh -c 'printf "two\n" >> a.txt; git add -A'
rv "$D" record >/dev/null
assert_eq "reviewed" "$(st "$D")" "a reviewed staged diff, before committing"
in_ "$D" git commit -qm second
assert_eq "reviewed" "$(st "$D")" "…and still reviewed after committing it"

# This is the case a SHA-based record gets wrong: the commit moved, the content did not.
suite "content, not commits"
D=$(repo)
in_ "$D" sh -c 'printf "x\n" >> a.txt; git add -A'
rv "$D" record >/dev/null
in_ "$D" git commit -qm c1
in_ "$D" git commit -q --amend -m "c1 reworded"
assert_eq "reviewed" "$(st "$D")" "rewording a commit does not invalidate its review"

D=$(repo)
in_ "$D" sh -c 'printf "x\n" >> a.txt; git add -A'
rv "$D" record >/dev/null
in_ "$D" git commit -qm c1
in_ "$D" sh -c 'printf "y\n" >> a.txt; git add -A; git commit -q --amend --no-edit'
assert_eq "no" "$(st "$D")" "amending in *new content* does invalidate it"

# ── what must not pass ───────────────────────────────────────────────────────
suite "unreviewed work is not reviewed"
D=$(repo)
in_ "$D" sh -c 'printf "x\n" >> a.txt; git add -A'
rv "$D" record >/dev/null
in_ "$D" git commit -qm c1
in_ "$D" sh -c 'printf "later\n" >> a.txt; git add -A; git commit -qm c2'
assert_eq "no" "$(st "$D")" "a commit made after the review is not covered"
assert_contains "$(rv "$D" status)" "1 of 2" "…and it says how many are uncovered"
assert_contains "$(rv "$D" status)" "critique-diff" "…and how to fix it"

# ── two reviews, two commits, one push ───────────────────────────────────────
# The ordinary way of working. Neither review matches the combined push diff, so an
# exact-match-only rule would call this unreviewed and be wrong.
suite "several reviews, one push"
D=$(repo)
in_ "$D" sh -c 'printf "one\n" >> a.txt; git add -A'
rv "$D" record >/dev/null
in_ "$D" git commit -qm c1
in_ "$D" sh -c 'printf "two\n" >> b.txt; git add -A'
rv "$D" record >/dev/null
in_ "$D" git commit -qm c2
assert_eq "reviewed" "$(st "$D")" "every commit reviewed separately counts as reviewed"

D=$(repo)
in_ "$D" sh -c 'printf "one\n" >> a.txt; git add -A'
rv "$D" record >/dev/null
in_ "$D" git commit -qm c1
in_ "$D" sh -c 'printf "two\n" >> b.txt; git add -A; git commit -qm c2'
assert_eq "no" "$(st "$D")" "…but one unreviewed commit among them is still no"

# ── unknown is not a soft no ─────────────────────────────────────────────────
suite "unknown never masquerades as no"
D=$(repo); rm -rf "$D/.aether"
assert_eq "unknown" "$(st "$D")" "a project with no .aether/ is unknown, not no"
assert_contains "$(rv "$D" record)" "nowhere to record" "…and record says why"

# Put every hasher out of reach. aether_sha fails closed by printing nothing, which is
# right for trust and wrong here: every record would hash to empty and match every other.
D=$(repo)
STUB=$(mktemp -d); WORK+=("$STUB")
for t in shasum sha256sum openssl; do printf '#!/bin/sh\nexit 127\n' > "$STUB/$t"; chmod +x "$STUB/$t"; done
nohash() { ( cd "$D" && env HOME="$D/home" AETHER_REPO="$REPO" PATH="$STUB:$PATH" \
             bash "$CLI" review "$@" 2>&1 ); }
assert_eq "unknown" "$(nohash status --raw)" "no sha256 tool reads as unknown"
assert_contains "$(nohash record)" "nothing was recorded" "…and record refuses rather than writing an empty hash"
[ -s "$D/.aether/out/.reviewed" ] && fail "no empty hash is written" "the file has content" \
                                  || pass "no empty hash is written"

# A repo with no remote ref at all — detaching HEAD is not enough, since origin/main
# still exists and is a perfectly good base.
D=$(repo)
in_ "$D" git update-ref -d refs/remotes/origin/main
assert_eq "unknown" "$(st "$D")" "no upstream or base to compare against is unknown"

# ── recording ────────────────────────────────────────────────────────────────
suite "recording"
D=$(repo)
assert_contains "$(rv "$D" record)" "Nothing in scope" "recording an empty diff records nothing"
in_ "$D" sh -c 'printf "x\n" >> a.txt; git add -A'
rv "$D" record >/dev/null
assert_eq "1" "$(grep -c . "$D/.aether/out/.reviewed")" "one record per review"
rv "$D" record >/dev/null
assert_eq "2" "$(grep -c . "$D/.aether/out/.reviewed")" "records append rather than overwrite"
assert_contains "$(cat "$D/.aether/out/.reviewed")" "staged" "the scope is recorded"

out=$(rv "$D" bogus); e=$?
assert_exit 1 "$e" "an unknown subcommand exits 1"
assert_contains "$out" "Try: status, show, list, record" "…and names the real ones"

# ── the commands call it ─────────────────────────────────────────────────────
# A slash command told to write a file *format* would drift; told to run a command, it
# cannot. Assert the contract exists in the command files.
suite "the critique commands record"
for f in critique-diff critique-pr; do
  assert_contains "$(cat "$REPO/plugins/temper/.claude/commands/$f.md")" "aether review record" \
    "/$f records the review"
done

summary
