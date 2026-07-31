#!/usr/bin/env bash
# tests/test_strict.sh — strict mode.
#
# Strict mode is the first thing in this suite that can stop someone working, so most of
# this file is about when it must *not* fire.
#
# A PreToolUse hook can stop a tool call two ways. Exit 2 is blunt and is exactly what
# bash returns for a syntax error, so a deliberate block and a half-written file would be
# indistinguishable — nothing here uses it. The other way is to exit 0 and print
# `permissionDecision: ask`, which escalates to the human. The agent cannot answer that
# prompt, which is the whole point: it is the first mechanism that takes the decision away
# from the thing writing the command.
#
# Two consequences under test throughout:
#   - breakage cannot forge an escalation, because a syntax error cannot print valid JSON
#   - `unknown` never escalates, because absence of evidence is not evidence

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

HOOK="$REPO/hooks/enforce-suite.sh"
WORK=()
cleanup() { for w in "${WORK[@]}"; do rm -rf "$w"; done; }
trap cleanup EXIT

# A repo with a critical-path file staged, so temper has a block verdict to escalate.
fixture() {
  local d; d=$(mktemp -d); WORK+=("$d")
  mkdir -p "$d/home/.aether" "$d/.aether"
  (
    cd "$d" || exit 1
    git init -q -b main . && git config user.email t@t && git config user.name t
    printf 'x\n' > seed.txt && git add -A && git commit -qm init
    git update-ref refs/remotes/origin/main HEAD
    printf 'secret\n' > auth.py && git add -A
  ) >/dev/null 2>&1
  printf '%s' "$d"
}

strict() { printf '[temper]\nstrict: %s\n' "$2" > "$1/home/.aether/config"; }

# fire <dir> <command> — sets $OUT and $RC.
#
# Deliberately NOT echoing the output: wrapping this in $( ) would run it in a subshell
# and $RC would never survive, which is the trap tests/lib.sh already warns about for
# run_standalone. Callers read $OUT.
fire() {
  OUT=$( cd "$1" && printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$2" \
         | env HOME="$1/home" bash "$HOOK" 2>&1 )
  RC=$?
}

decision() {   # the permissionDecision, or "" if the output is not a decision
  printf '%s' "$1" | python3 -c 'import json,sys
try: print(json.loads(sys.stdin.read())["hookSpecificOutput"]["permissionDecision"])
except Exception: print("")' 2>/dev/null
}

# ── off is the default, and changes nothing ──────────────────────────────────
suite "strict is off by default"
D=$(fixture)
fire "$D" 'git commit -m x'; out="$OUT"
assert_exit 1 "$RC" "a block still exits 1"
assert_contains "$out" "temper: critical path" "…and still prints plain text"
assert_eq "" "$(decision "$out")" "no decision is emitted"

# ── on, it escalates ─────────────────────────────────────────────────────────
suite "strict: blocks escalates"
D=$(fixture); strict "$D" blocks
fire "$D" 'git commit -m x'; out="$OUT"
assert_exit 0 "$RC" "escalation exits 0 — the decision travels as JSON, not as a code"
assert_eq "ask" "$(decision "$out")" "the decision is ask, not deny"
assert_contains "$out" "critical path" "the reason carries the gate's own words"

# The JSON must be the only thing on stdout, or it is not JSON at all.
if printf '%s' "$out" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then
  pass "stdout is exactly one JSON document"
else
  fail "stdout is exactly one JSON document" "${out:0:90}"
fi

# ── what must never escalate ─────────────────────────────────────────────────
suite "nudges are not escalated"
D=$(fixture); strict "$D" blocks
( cd "$D" && git reset -q && rm -f auth.py && printf 'x\n' > plain.txt && git add -A ) >/dev/null 2>&1
fire "$D" 'git commit -m wip'; out="$OUT"
assert_eq "" "$(decision "$out")" "a weak commit message is a nudge, and stays one"
assert_exit 1 "$RC" "…exiting 1 as before"

suite "unknown never escalates"
# No .aether/ means no review record is possible, so the push verdict is `unknown`.
# A prompt nobody can ever satisfy is the fastest way to get strict mode switched off.
D=$(fixture); strict "$D" blocks; rm -rf "$D/.aether"
fire "$D" 'git push origin main'; out="$OUT"
assert_eq "" "$(decision "$out")" "a push with no review record does not escalate"
assert_contains "$out" "could not be determined" "…and says the question was unanswerable"

suite "hostile input never escalates"
# Malformed input is not evidence of anything. Both modes, because a parse failure that
# escalated would be a way to trigger prompts by sending rubbish.
for level in off blocks; do
  D=$(fixture); strict "$D" "$level"
  for payload in 'not json at all' '' '{}' '{"tool_name":"Bash","tool_input":{"command":null}}'; do
    out=$( cd "$D" && printf '%s' "$payload" | env HOME="$D/home" bash "$HOOK" 2>&1 ); rc=$?
    if [ -z "$(decision "$out")" ] && [ "$rc" -ne 2 ]; then
      pass "strict:$level, hostile payload does not escalate or exit 2"
    else
      fail "strict:$level, hostile payload does not escalate or exit 2" "rc=$rc out=${out:0:60}"
    fi
  done
done

# ── the bypass still wins ────────────────────────────────────────────────────
suite "the marker still suppresses"
D=$(fixture); strict "$D" blocks
fire "$D" 'git commit -m x # temper:skip'; out="$OUT"
assert_eq "" "$(decision "$out")" "a trailing marker suppresses the gate before it runs"
case "$out" in
  *"critical path"*) fail "…so temper's block never happens" "temper still spoke" ;;
  *) pass "…so temper's block never happens" ;;
esac
# The marker is per plugin: cairn still nudges the one-character message, which is why
# the hook is not silent. `# aether:skip` is the one that silences everything.
fire "$D" 'git commit -m x # aether:skip'; out="$OUT"
assert_exit 0 "$RC" "# aether:skip silences the hook entirely"
assert_eq "" "$out" "…with no output at all"

# ── the switch is global-only ────────────────────────────────────────────────
suite "the switch is global-only"
# A project-level switch would sit in the tree the agent is editing. The value of strict
# mode is that turning it off is conspicuous, so a repo cannot turn it on or off.
D=$(fixture)
printf '[temper]\nstrict: blocks\n' > "$D/.aether/config"
fire "$D" 'git commit -m x'; out="$OUT"
assert_eq "" "$(decision "$out")" "a project config cannot switch strict on"

D=$(fixture); strict "$D" blocks
printf '[temper]\nstrict: off\n' > "$D/.aether/config"
fire "$D" 'git commit -m x'; out="$OUT"
assert_eq "ask" "$(decision "$out")" "…and cannot switch it off either"

# ── the key is declared ──────────────────────────────────────────────────────
# The release before this one shipped `aether docs`, which reports config keys no
# manifest declares. An undeclared `strict` would fail this project's own checker.
suite "strict is a declared key"
assert_contains "$(cd "$REPO" && bash bin/aether config show temper 2>&1)" "strict" \
  "aether config show lists it"
out=$(cd "$REPO" && bash bin/aether config doctor 2>&1)
case "$out" in
  *"strict"*unknown*) fail "config doctor accepts it" "reported as unknown" ;;
  *) pass "config doctor accepts it" ;;
esac

# ── the residual fail-open risk, stated rather than assumed ──────────────────
# A corrupt hook file exits 2, which Claude Code reads as "block", and nothing can guard
# against that from inside the file — bash parses it before any of its code runs. What
# keeps it from happening is that the engine never writes a partial file: _op_copy writes
# to a temp and renames, which is atomic. Assert that property, since it is the mitigation.
suite "the engine cannot leave a half-written hook"
src=$(sed -n '/^_op_copy()/,/^}/p' "$REPO/bin/aether")
case "$src" in
  *'mv -f "$tmp" "$dst"'*) pass "_op_copy renames into place rather than writing in place" ;;
  *) fail "_op_copy renames into place rather than writing in place" "no atomic rename found" ;;
esac

summary
