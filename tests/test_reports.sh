#!/usr/bin/env bash
# tests/test_reports.sh — reading the critiques back.
#
# The reports were written and then effectively lost: one real repository accumulated 21
# reviews in 357 lines, and seeing the latest took
# `awk '/^# Review/{n++} n==21'`.
#
# Two properties carry most of the weight here:
#
#   1. **Backwards compatibility is load-bearing.** Entries written before the marker
#      existed must still list and show. A reader that only understood the new format
#      would make every report already on disk invisible, which is worse than the awk.
#   2. **The prose cannot be trusted to have one shape.** The counts were written by a
#      model, and across one real history the same three numbers appear as
#      `**Blockers:** 0`, `**Blockers:** 0 | **Significant:** 3 | **Minor:** 4`, and
#      `**Blockers:** 0 — … — Good to ship`. Stripping digits from the whole line turned
#      `2 | 3 | 4` into 234, which is what the label-scoped parse exists to prevent.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

CLI="$REPO/bin/aether"
WORK=()
cleanup() { for w in "${WORK[@]}"; do rm -rf "$w"; done; }
trap cleanup EXIT

proj() {
  local d; d=$(mktemp -d); WORK+=("$d")
  mkdir -p "$d/home" "$d/.aether/out"
  printf '%s' "$d"
}
ae() { ( cd "$1" && env HOME="$1/home" AETHER_REPO="$REPO" bash "$CLI" "${@:2}" 2>&1 ); }

# An unmarked entry, the pre-1.8 shape. $4 is the counts line, whose format varies.
legacy() {
  cat >> "$1/.aether/out/TEMPER.md" <<EOF

# Review — $2 — $3

Body of $2.

$4
EOF
}

# ── unmarked entries: everything already on disk ─────────────────────────────
suite "pre-1.8 reports are still readable"
D=$(proj)
legacy "$D" "first"  "2026-05-07" '**Blockers:** 0
**Significant:** 1
**Minor:** 5'
legacy "$D" "second" "2026-05-07" '**Blockers:** 0 | **Significant:** 0 | **Minor:** 3'
legacy "$D" "third"  "2026-06-26" '**Blockers:** 2 | **Significant:** 3 | **Minor:** 4'

out=$(ae "$D" review list)
assert_contains "$out" "3 entries" "all three are listed"
assert_contains "$out" "2026-06-26" "the date comes from the heading"

raw=$(ae "$D" review list --raw)
assert_eq "0	1	5" "$(printf '%s\n' "$raw" | awk -F'\t' '$1==1 {print $4"\t"$5"\t"$6}')" \
  "counts on separate lines"
assert_eq "0	0	3" "$(printf '%s\n' "$raw" | awk -F'\t' '$1==2 {print $4"\t"$5"\t"$6}')" \
  "counts on one pipe-separated line"
# The regression: stripping non-digits from the whole line made this 234.
assert_eq "2	3	4" "$(printf '%s\n' "$raw" | awk -F'\t' '$1==3 {print $4"\t"$5"\t"$6}')" \
  "counts on one line are read per label, not concatenated"

assert_contains "$(ae "$D" review show)" "Body of third" "show gives the latest"
assert_contains "$(ae "$D" review show 1)" "Body of first" "show N gives the Nth"
case "$(ae "$D" review show 1)" in
  *"Body of second"*) fail "show N stops at the next entry" "bled into the next" ;;
  *) pass "show N stops at the next entry" ;;
esac

# Two entries on the same day with identical headings — the collision that prompted this.
suite "same-day entries are addressable"
D=$(proj)
legacy "$D" "staged diff" "2026-05-07" '**Blockers:** 0
**Significant:** 1'
legacy "$D" "staged diff" "2026-05-07" '**Blockers:** 1
**Significant:** 0'
raw=$(ae "$D" review list --raw)
assert_eq "2" "$(printf '%s\n' "$raw" | grep -c .)" "byte-identical headings are two entries"
assert_eq "0" "$(printf '%s\n' "$raw" | awk -F'\t' '$1==1 {print $4}')" "…the first keeps its counts"
assert_eq "1" "$(printf '%s\n' "$raw" | awk -F'\t' '$1==2 {print $4}')" "…and the second keeps its own"

# ── marked entries ───────────────────────────────────────────────────────────
suite "marked reports"
D=$(proj)
cat >> "$D/.aether/out/TEMPER.md" <<'EOF'

<!-- aether:review date=2026-07-31T12:04Z scope=all blockers=0 significant=1 minor=4 -->
# Review — all changes since HEAD — 2026-07-31

Marked body.

**Blockers:** 0
**Significant:** 1
**Minor:** 4
<!-- /aether:review -->
EOF
out=$(ae "$D" review list)
assert_contains "$out" "2026-07-31T12:04Z" "the marker supplies a timestamp, not just a date"
assert_contains "$out" "all" "…and the scope"

body=$(ae "$D" review show --raw)
assert_contains "$body" "Marked body." "show prints the body"
case "$body" in
  *"aether:review"*) fail "markers are delimiters, not content" "a marker line was printed" ;;
  *) pass "markers are delimiters, not content" ;;
esac

# Mixed in one file, which is what every existing history becomes after the next review.
suite "marked and unmarked in one file"
D=$(proj)
legacy "$D" "old one" "2026-05-07" '**Blockers:** 1'
cat >> "$D/.aether/out/TEMPER.md" <<'EOF'

<!-- aether:review date=2026-07-31T12:04Z scope=staged blockers=0 significant=2 minor=0 -->
# Review — staged diff — 2026-07-31

New one.
<!-- /aether:review -->
EOF
raw=$(ae "$D" review list --raw)
assert_eq "2" "$(printf '%s\n' "$raw" | grep -c .)" "both shapes are counted"
assert_contains "$(ae "$D" review show 1)" "Body of old one" "the unmarked one is addressable"
assert_contains "$(ae "$D" review show 2)" "New one" "…and so is the marked one"

# ── a heading inside a fence must not split the entry ────────────────────────
suite "fenced code is not a heading"
D=$(proj)
cat >> "$D/.aether/out/TEMPER.md" <<'EOF'

# Review — staged diff — 2026-07-31

Quoting the format:

```
# Review — something — 2026-01-01
```

**Blockers:** 0
EOF
assert_eq "1" "$(ae "$D" review list --raw | grep -c .)" "a # Review line inside a fence does not split"
assert_contains "$(ae "$D" review show)" "Quoting the format" "…and the entry stays whole"

# ── nothing to show ──────────────────────────────────────────────────────────
suite "nothing to show"
D=$(proj)
out=$(ae "$D" review show); e=$?
assert_exit 0 "$e" "no file exits 0 — this is a reader, not a check"
assert_contains "$out" "No reviews recorded" "…and says so"
assert_contains "$out" "critique-diff" "…and how to get one"

: > "$D/.aether/out/TEMPER.md"
assert_contains "$(ae "$D" review list)" "no reviews" "an empty file says so"

legacy "$D" "no counts" "2026-07-31" ''
assert_eq "0	0	0" "$(ae "$D" review list --raw | awk -F'\t' '{print $4"\t"$5"\t"$6}')" \
  "a report with no counts reads as zeros rather than failing"

out=$(ae "$D" review show 99)
assert_contains "$out" "No review numbered 99" "an out-of-range index says so"

# ── the pre-1.1 location ─────────────────────────────────────────────────────
# The reader must mirror the writer: keep to .claude/plans/TEMPER.md only while it
# exists and .aether/out/ does not, so a second history is never started.
suite "the pre-1.1 location"
D=$(mktemp -d); WORK+=("$D"); mkdir -p "$D/home" "$D/.claude/plans"
cat > "$D/.claude/plans/TEMPER.md" <<'EOF'
# Review — staged diff — 2026-01-01

Old location.

**Blockers:** 0
EOF
assert_contains "$(ae "$D" review show)" "Old location" "a pre-1.1 file is found"
mkdir -p "$D/.aether/out"
assert_contains "$(ae "$D" review show)" "No reviews recorded" \
  "…and abandoned once .aether/ exists, which is where the writer moves to"

# ── plan critique ────────────────────────────────────────────────────────────
suite "plan critique"
D=$(proj); mkdir -p "$D/.claude/plans"
P="$D/.claude/plans/p.md"
printf '# A plan\n\nDo the thing.\n' > "$P"
printf '%s\n' "$P" > "$D/.aether/out/.plan"
out=$(ae "$D" plan critique)
assert_contains "$out" "no critique on record" "an uncritiqued plan says so"
assert_contains "$out" "critique-plan" "…and how to fix it"

H=$( cd "$D" && env HOME="$D/home" AETHER_REPO="$REPO" bash "$CLI" plan hash "$P" )
cat >> "$P" <<EOF

<!-- aether:critique sha=$H date=2026-07-31 blockers=0 -->
## Critique — 2026-07-31
The finding.
<!-- /aether:critique -->
EOF
out=$(ae "$D" plan critique)
assert_contains "$out" "The finding." "a critiqued plan prints its critique"
case "$out" in
  *"aether:critique"*) fail "the marker is not printed" "marker leaked into the output" ;;
  *) pass "the marker is not printed" ;;
esac

printf '\nA new section, added after the critique.\n' >> "$P"
out=$(ae "$D" plan critique)
assert_contains "$out" "The finding." "a stale critique is still shown — it is what was said"
assert_contains "$out" "changed after this critique" "…but flagged as stale"

# ── help ─────────────────────────────────────────────────────────────────────
# All three answered `Unknown: …` before, which is what someone hits first.
suite "every noun answers --help"
for noun in review plan config; do
  out=$(ae "$D" "$noun" --help); e=$?
  assert_exit 0 "$e" "aether $noun --help exits 0"
  assert_contains "$out" "aether $noun <subcommand>" "…and lists its subcommands"
done
assert_contains "$(ae "$D" plan bogus)" "critique" "the plan fallthrough names the new subcommand"

summary
