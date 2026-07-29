#!/usr/bin/env bash
# tests/test_config.sh — the sectioned config, its schema, and migration.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

CLI="$REPO/bin/aether"
LIB="$REPO/hooks/aether-config.sh"

TMPS=()
mk() { local d; d=$(mktemp -d); TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { for d in "${TMPS[@]}"; do rm -rf "$d"; done; }
trap cleanup EXIT

# ── per-key resolution ───────────────────────────────────────────────────────
# The property worth protecting: a project file overrides only the keys it names.
# Setting one key in a repo must not discard the global value of its neighbours.
suite "per-key merge across sections"
H=$(mk); P=$(mk)
mkdir -p "$H/.aether" "$P/.aether"
cat > "$H/.aether/config" <<'EOF'
enabled: true

[temper]
auto_nudge_lines: 200
severity: red, yellow

[cairn]
style: conventional
EOF
cat > "$P/.aether/config" <<'EOF'
[temper]
auto_nudge_lines: 400
EOF

cfg() { ( cd "$P" && HOME="$H" bash -c ". '$LIB'; aether_cfg_get \"\$1\" \"\$2\"" _ "$1" "$2" ); }
assert_eq "400"         "$(cfg temper auto_nudge_lines)" "project overrides the key it names"
assert_eq "red, yellow" "$(cfg temper severity)"         "a sibling key keeps its global value"
assert_eq "conventional" "$(cfg cairn style)"            "another section is untouched"
assert_eq "true"        "$(cfg '' enabled)"              "a key outside any section resolves"
assert_eq ""            "$(cfg temper nope)"             "an undeclared key resolves empty"

# A duplicated key must yield one line. Two of the four pre-1.0 parsers were
# missing `head -1`, so half the suite saw a multi-line value here.
printf '\n[temper]\ndiff: all\ndiff: staged\n' >> "$P/.aether/config"
assert_eq "all" "$(cfg temper diff)" "a duplicated key yields exactly one value"

# ── config show ──────────────────────────────────────────────────────────────
suite "config show"
out=$( cd "$P" && env HOME="$H" bash "$CLI" config show temper 2>&1 )
assert_contains "$out" "auto_nudge_lines"      "show lists the key"
assert_contains "$out" "project · .aether/config" "show names the project as the source"
assert_contains "$out" "global ·"              "show names global for the inherited key"
assert_contains "$out" "default"               "show marks unset keys as default"
assert_contains "$out" "Nudge before a commit" "show prints the doc line"
assert_contains "$out" "used by:"              "show prints what consumes the key"

out=$( cd "$P" && env HOME="$H" bash "$CLI" config show temper --values 2>&1 )
case "$out" in
  *"Nudge before a commit"*) fail "--values drops the prose" "doc line still printed" ;;
  *) pass "--values drops the prose" ;;
esac

# ── every key is documented ──────────────────────────────────────────────────
# A key with no doc and no used_by is a key nobody can discover: it appears in
# `config show` as a bare name, and there is nothing to grep for.
suite "schema completeness"
undocumented=""
for m in "$REPO"/plugins/*/aether.plugin; do
  plugin=$(basename "$(dirname "$m")")
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    grep -q "^config\.$key\.used_by:" "$m" || undocumented="$undocumented $plugin.$key(used_by)"
    d=$(sed -n "s/^config\.$key\.doc: *//p" "$m")
    [ -n "$d" ] || undocumented="$undocumented $plugin.$key(doc)"
  done <<EOF
$(sed -n 's/^config\.\(.*\)\.doc:.*/\1/p' "$m")
EOF
done
[ -z "$undocumented" ] \
  && pass "every declared key has a doc and a used_by" \
  || fail "every declared key has a doc and a used_by" "missing:$undocumented"

n=$( for m in "$REPO"/plugins/*/aether.plugin; do sed -n 's/^config\..*\.doc:.*/x/p' "$m"; done | wc -l | tr -d ' ')
[ "$n" -ge 30 ] \
  && pass "the schema covers $n keys" \
  || fail "the schema covers enough keys" "only $n declared"

# ── config doctor ────────────────────────────────────────────────────────────
suite "config doctor"
H2=$(mk); P2=$(mk); mkdir -p "$H2/.aether" "$P2/.aether"
cat > "$P2/.aether/config" <<'EOF'
[temper]
auto_nudge_line: 400

[cairn]
styl: plain

[project]
typecheck: definitely-not-a-real-binary --check
EOF
out=$( cd "$P2" && env HOME="$H2" bash "$CLI" config doctor 2>&1 )
assert_contains "$out" "auto_nudge_line — unknown key"  "doctor reports an unknown key"
assert_contains "$out" "did you mean auto_nudge_lines?" "doctor suggests the intended key"
assert_contains "$out" "did you mean style?"            "doctor suggests across sections"
assert_contains "$out" "not on PATH"                    "doctor flags a command that cannot run"

# The point of catching typos: the value silently does nothing today.
got=$( cd "$P2" && env HOME="$H2" bash "$CLI" config get temper.auto_nudge_lines 2>&1 )
assert_eq "200" "$got" "the typo'd key really was being ignored (default still applies)"

# ── set / unset preserve the file ────────────────────────────────────────────
suite "config set and unset"
H3=$(mk); mkdir -p "$H3/.aether"
cat > "$H3/.aether/config" <<'EOF'
# a comment the user wrote
enabled: true

[temper]
severity: red
EOF
env HOME="$H3" bash "$CLI" config set temper.auto_nudge_lines 400 global >/dev/null 2>&1
env HOME="$H3" bash "$CLI" config set cairn.style plain global        >/dev/null 2>&1
body=$(cat "$H3/.aether/config")
assert_contains "$body" "# a comment the user wrote" "set preserves the user's comments"
assert_contains "$body" "severity: red"              "set preserves neighbouring keys"
assert_contains "$body" "auto_nudge_lines: 400"      "set adds to an existing section"
assert_contains "$body" "[cairn]"                    "set creates a missing section"
assert_contains "$body" "Nudge before a commit"      "set writes the doc line above the key"

before=$(cat "$H3/.aether/config")
env HOME="$H3" bash "$CLI" config set temper.auto_nudge_lines 400 global >/dev/null 2>&1
assert_eq "$before" "$(cat "$H3/.aether/config")" "setting the same value again changes nothing"

env HOME="$H3" bash "$CLI" config unset temper.auto_nudge_lines global >/dev/null 2>&1
case "$(cat "$H3/.aether/config")" in
  *"auto_nudge_lines: 400"*) fail "unset removes the key" "still present" ;;
  *) pass "unset removes the key" ;;
esac
assert_contains "$(cat "$H3/.aether/config")" "severity: red" "unset leaves the rest alone"

# ── pre-migration files are still read ───────────────────────────────────────
# A machine that has not migrated must keep working, or an upgrade silently
# resets everyone's thresholds to the defaults.
suite "pre-1.0 config still resolves"
H4=$(mk); mkdir -p "$H4/.claude"
printf 'auto_nudge_lines: 999\nseverity: red\n' > "$H4/.claude/temper.config"
P4=$(mk)
old() { ( cd "$P4" && HOME="$H4" bash -c ". '$LIB'; aether_cfg_get \"\$1\" \"\$2\"" _ "$1" "$2" ); }
assert_eq "999" "$(old temper auto_nudge_lines)" "the old global file is still read"
printf 'auto_nudge_lines: 350\n' > "$P4/temper.config"
assert_eq "350" "$(old temper auto_nudge_lines)" "the old project file still wins over global"

# ── migration ────────────────────────────────────────────────────────────────
suite "migration"
H5=$(mk); P5=$(mk)
mkdir -p "$H5/.claude/plans" "$H5/.cairn" "$P5/.claude/plans"
printf 'auto_nudge_lines: 999\nseverity: red\n'              > "$H5/.claude/temper.config"
printf 'style: plain\npr.rules_file: %s/.cairn/pr-rules.md\n' "$H5" > "$H5/.claude/cairn.config"
printf 'critics: impl\n'                                     > "$H5/.claude/whetstone.config"
printf 'Always mention the ticket ID.\n'                     > "$H5/.cairn/pr-rules.md"
printf 'version=1.0.0\nscope=global\n'                       > "$H5/.claude/aether.manifest"
printf 'auto_nudge_lines: 350\n'                             > "$P5/temper.config"
printf 'This project uses event sourcing.\n'                 > "$P5/whetstone.config.md"
printf '# old critique\n'                                    > "$P5/.claude/plans/CRITIQUE.md"
printf '# my plan\n'                                         > "$P5/.claude/plans/my-plan.md"

( cd "$P5" && env HOME="$H5" bash "$CLI" migrate >/dev/null 2>&1 )

g="$H5/.aether/config"; l="$P5/.aether/config"
assert_contains "$(cat "$g")" "auto_nudge_lines: 999" "global value survives the move"
assert_contains "$(cat "$g")" "[temper]"              "…under its own section"
assert_contains "$(cat "$g")" "[whetstone]"           "every plugin gets a section"
assert_contains "$(cat "$l")" "auto_nudge_lines: 350" "the project value survives too"

res() { ( cd "$P5" && HOME="$H5" bash -c ". '$LIB'; aether_cfg_get \"\$1\" \"\$2\"" _ "$1" "$2" ); }
assert_eq "350" "$(res temper auto_nudge_lines)" "precedence is unchanged after migrating"
assert_eq "red" "$(res temper severity)"         "and the inherited key still resolves"

assert_contains "$(cat "$P5/.aether/rules.md")" "event sourcing" "whetstone.config.md becomes rules.md"
assert_contains "$(cat "$P5/.aether/rules.md")" "[critique-plan]" "…under the command that reads it"
assert_contains "$(cat "$H5/.aether/rules.md")" "[draft-pr]"      "pr.rules_file is imported globally"
# A global pr.rules_file must not be copied into every project that migrates.
case "$(cat "$P5/.aether/rules.md")" in
  *"[draft-pr]"*) fail "a global pr.rules_file stays global" "it leaked into the project" ;;
  *) pass "a global pr.rules_file stays global" ;;
esac

[ -f "$P5/.aether/out/CRITIQUE.md" ] && pass "generated output moves to out/" \
                                     || fail "generated output moves to out/"
[ -f "$P5/.claude/plans/my-plan.md" ] && pass "the user's own plan file stays put" \
                                      || fail "the user's own plan file stays put"
[ -f "$H5/.claude/temper.config.bak" ] && pass "the old file is backed up before removal" \
                                       || fail "the old file is backed up before removal"
[ -f "$H5/.claude/temper.config" ] && fail "the old file is removed" \
                                   || pass "the old file is removed"

# Idempotent: an interrupted run must finish on the next attempt, and a
# completed one must be a no-op rather than duplicating prose.
before_g=$(cat "$g"); before_r=$(cat "$P5/.aether/rules.md")
( cd "$P5" && env HOME="$H5" bash "$CLI" migrate >/dev/null 2>&1 )
assert_eq "$before_g" "$(cat "$g")"                  "re-running migrate leaves config unchanged"
assert_eq "$before_r" "$(cat "$P5/.aether/rules.md")" "re-running migrate does not duplicate prose"

# ── new wins over old ────────────────────────────────────────────────────────
suite "migration does not overwrite a migrated value"
H6=$(mk); P6=$(mk); mkdir -p "$H6/.claude" "$H6/.aether"
printf 'auto_nudge_lines: 999\n' > "$H6/.claude/temper.config"
printf '[temper]\nauto_nudge_lines: 111\n' > "$H6/.aether/config"
# cd into a throwaway project first: `migrate` acts on the current directory as
# well as on HOME, so running it from the repo migrates the repo.
( cd "$P6" && env HOME="$H6" bash "$CLI" migrate >/dev/null 2>&1 )
assert_contains "$(cat "$H6/.aether/config")" "auto_nudge_lines: 111" "the already-migrated value wins"
case "$(cat "$H6/.aether/config")" in
  *999*) fail "the old value does not come back" "999 was written over 111" ;;
  *) pass "the old value does not come back" ;;
esac

# ── one reader, not six ──────────────────────────────────────────────────────
# The gates and the CLI must not carry separate parsers again.
suite "single config reader"
for f in "$REPO/hooks/enforce-suite.sh" \
         "$REPO/plugins/temper/hooks/enforce-temper.sh"; do
  n=$(grep -c 'grep "\^\$key:"\|grep "\^enabled:"' "$f" 2>/dev/null || true)
  [ "$n" -eq 0 ] \
    && pass "$(basename "$f") has no parser of its own" \
    || fail "$(basename "$f") has no parser of its own" "$n hand-rolled read(s) remain"
done
grep -q 'aether_cfg_get' "$REPO/hooks/enforce-suite.sh" \
  && pass "the dispatcher reads config through the shared library" \
  || fail "the dispatcher reads config through the shared library"

# The library has to work with nothing else sourced — that is how a gate uses it.
out=$(bash -c ". '$LIB'; aether_cfg_get temper severity; printf 'ok'" 2>&1)
assert_contains "$out" "ok" "the library is sourceable on its own"

summary
