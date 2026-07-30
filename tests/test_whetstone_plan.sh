#!/usr/bin/env bash
# tests/test_whetstone_plan.sh — plans, their critiques, and the gate that reads them.
#
# Order matters. The fallback guard comes first, because the safety argument for all of
# this is "a project that has not recorded a plan behaves exactly as it did". Then the
# regression that started it: the gate could not see a plan written by plan mode.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

CLI="$REPO/bin/aether"
LIB="$REPO/hooks/aether-config.sh"
GATE="$REPO/plugins/whetstone/hooks/enforce-whetstone.sh"
POST="$REPO/plugins/whetstone/hooks/post-whetstone.sh"

TMPS=()
mk() { local d; d=$(mktemp -d); TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# A project with a git repo, since the commit gate needs one.
newproj() {
  local d; d=$(mk); mkdir -p "$d/src"
  ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t )
  printf '%s' "$d"
}
# <home> <proj> <label> <payload>  → "exit<TAB>first line of output"
fire() {
  local h="$1" p="$2" payload="$3" out rc
  out=$( cd "$p" && printf '%s' "$payload" | env HOME="$h" bash "$GATE" 2>&1 ); rc=$?
  printf '%s\t%s' "$rc" "$(printf '%s' "$out" | head -1)"
}
record() { ( cd "$2" && printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$3" \
             | env HOME="$1" bash "$POST" >/dev/null 2>&1 ); }
critique() {  # <plan file> [blockers]
  local f="$1" h; h=$( . "$LIB"; aether_plan_hash "$f" )
  printf '\n<!-- aether:critique sha=%s date=2026-07-30 blockers=%s -->\n' "$h" "${2:-0}" >> "$f"
  printf '## Critique\n\nNothing to flag.\n<!-- /aether:critique -->\n' >> "$f"
}
PUSH='{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}'
EXITPM='{"tool_name":"ExitPlanMode","tool_input":{}}'

# ── 1. the fallback: a project that has recorded no plan is unaffected ───────
suite "a project with no recorded plan behaves as before"
H=$(mk); P=$(newproj); mkdir -p "$H/.aether" "$P/.claude/plans"
printf '# old plan\nbody\n' > "$P/.claude/plans/old.md"
r=$(fire "$H" "$P" "$PUSH")
assert_eq "1" "${r%%	*}" "an uncritiqued project plan still nudges at commit"

# The pre-1.4 arrangement: no in-plan marker, but a CRITIQUE.md newer than the plan.
mkdir -p "$P/.aether/out"; printf '# Critique\nfine\n' > "$P/.aether/out/CRITIQUE.md"
r=$(fire "$H" "$P" "$PUSH")
assert_eq "0" "${r%%	*}" "a project critiqued the old way is not told to do it again"

# ── 2. the regression: a plan written by plan mode ──────────────────────────
# The gate globbed ./.claude/plans/*.md, and plan mode writes to ~/.claude/plans/ —
# so it never saw the plan at all and judged whatever stale file was in the project.
suite "the gate sees a plan in the global plans directory"
H=$(mk); P=$(newproj); mkdir -p "$H/.claude/plans"
PLAN="$H/.claude/plans/feature.md"
printf '# A plan\n\nDo the thing.\n' > "$PLAN"
record "$H" "$P" "$PLAN"
assert_eq "$PLAN" "$( cd "$P" && env HOME="$H" bash "$CLI" plan path )" \
  "the recorded plan is the one plan mode wrote"
r=$(fire "$H" "$P" "$PUSH")
assert_eq "1" "${r%%	*}" "…and an uncritiqued one nudges at commit"
assert_contains "${r#*	}" "not been critiqued" "…saying so"

critique "$PLAN"
r=$(fire "$H" "$P" "$PUSH")
assert_eq "0" "${r%%	*}" "a critique inside the plan satisfies the gate"

# ── 3. content hashing, not mtime ───────────────────────────────────────────
suite "staleness is content, not timestamps"
touch "$PLAN"
r=$(fire "$H" "$P" "$PUSH")
assert_eq "0" "${r%%	*}" "touching the plan does not invalidate its critique"

printf '\n## A section added after the critique\n' >> "$PLAN"
r=$(fire "$H" "$P" "$PUSH")
assert_eq "1" "${r%%	*}" "appending to the plan does invalidate it"
assert_contains "${r#*	}" "changed after its last critique" "…and says why"

# Editing only the critique text must not invalidate the plan.
H2=$(mk); P2=$(newproj); mkdir -p "$H2/.claude/plans"
PL2="$H2/.claude/plans/x.md"; printf '# P\nbody\n' > "$PL2"; record "$H2" "$P2" "$PL2"
critique "$PL2"
( cd "$P2" && env HOME="$H2" bash -c ". '$LIB'; aether_plan_state '$PL2'" ) >/dev/null
printf 'a further remark inside the critique\n' >> "$PL2"   # still inside? no — after the close tag
assert_eq "stale" "$( . "$LIB"; aether_plan_state "$PL2" )" \
  "text after the closing tag counts as plan content"

# ── 4. per plan, not per project ────────────────────────────────────────────
# One CRITIQUE.md for a whole project meant critiquing plan A satisfied the gate for
# plan B. A critique that lives in its plan cannot do that.
suite "a critique covers one plan"
H=$(mk); P=$(newproj); mkdir -p "$H/.claude/plans"
A="$H/.claude/plans/a.md"; B="$H/.claude/plans/b.md"
printf '# A\nbody\n' > "$A"; printf '# B\nbody\n' > "$B"
record "$H" "$P" "$A"; critique "$A"
r=$(fire "$H" "$P" "$PUSH"); assert_eq "0" "${r%%	*}" "plan A critiqued → silent"
record "$H" "$P" "$B"
r=$(fire "$H" "$P" "$PUSH"); assert_eq "1" "${r%%	*}" "switching to uncritiqued plan B → nudges"

# ── 5. the source-write nudge fires once per plan version ───────────────────
# The old sentinel was one empty file per project, so after the first nudge this gate
# was decorative — silent for every later plan.
suite "the source-write nudge is per plan version"
H=$(mk); P=$(newproj); mkdir -p "$H/.claude/plans"
A="$H/.claude/plans/a.md"; printf '# A\nbody\n' > "$A"; record "$H" "$P" "$A"
W='{"tool_name":"Write","tool_input":{"file_path":"src/x.py"}}'
r=$(fire "$H" "$P" "$W"); assert_eq "1" "${r%%	*}" "the first source write nudges"
r=$(fire "$H" "$P" '{"tool_name":"Write","tool_input":{"file_path":"src/y.py"}}')
assert_eq "0" "${r%%	*}" "…and not again for the same plan"
B="$H/.claude/plans/b.md"; printf '# B\nbody\n' > "$B"; record "$H" "$P" "$B"
r=$(fire "$H" "$P" "$W"); assert_eq "1" "${r%%	*}" "…but does for a different uncritiqued plan"

# A non-source file never nudges.
r=$(fire "$H" "$P" '{"tool_name":"Write","tool_input":{"file_path":"README.md"}}')
assert_eq "0" "${r%%	*}" "a non-source write never nudges"

# ── 6. ExitPlanMode ─────────────────────────────────────────────────────────
# Returns 0 unconditionally. Whether Claude Code delivers PreToolUse for this tool, or
# what it does with a non-zero exit, could not be determined from outside — and a nudge
# that trapped you in plan mode while intercepting the calls the critique needs would
# be far worse than no nudge. So it prints and never gates.
suite "ExitPlanMode prints but never gates"
H=$(mk); P=$(newproj); mkdir -p "$H/.claude/plans"
A="$H/.claude/plans/a.md"; printf '# A\nbody\n' > "$A"; record "$H" "$P" "$A"
r=$(fire "$H" "$P" "$EXITPM")
assert_eq "0" "${r%%	*}" "exit 0 even when uncritiqued — it must never block plan mode"
assert_contains "${r#*	}" "no critique on record" "…while still saying so"
critique "$A"
r=$(fire "$H" "$P" "$EXITPM")
assert_eq "0	" "$r" "silent once the plan is critiqued"
[ -f "$P/.aether/out/.exitplanmode-seen" ] \
  && pass "the gate records having seen an ExitPlanMode payload" \
  || fail "the gate records having seen an ExitPlanMode payload"

# The other three gates receive this payload too, since the matcher is shared.
suite "the other gates stay silent on ExitPlanMode"
for g in cairn temper bonsai; do
  out=$( cd "$P" && printf '%s' "$EXITPM" \
         | env HOME="$H" bash "$REPO/plugins/$g/hooks/enforce-$g.sh" 2>&1 ); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then pass "$g is silent on ExitPlanMode"
  else fail "$g is silent on ExitPlanMode" "exit=$rc out=${out:0:60}"; fi
done

# The dispatcher must route the tool, not only the matcher admit it. Widening the
# matcher alone left the hook invoked and dispatching nothing — it looked wired up and
# was not.
suite "the dispatcher routes ExitPlanMode"
grep -q 'ExitPlanMode)' "$REPO/hooks/enforce-suite.sh" \
  && pass "enforce-suite.sh has an ExitPlanMode branch" \
  || fail "enforce-suite.sh has an ExitPlanMode branch" "matcher widened but nothing dispatched"
HD=$(mk); PD=$(newproj); mkdir -p "$HD/.claude/plans"
AD="$HD/.claude/plans/a.md"; printf '# A\nbody\n' > "$AD"; record "$HD" "$PD" "$AD"
mkdir -p "$PD/.aether/hooks/gates"
cp "$REPO/hooks/aether-config.sh" "$PD/.aether/hooks/"
cp "$GATE" "$PD/.aether/hooks/gates/enforce-whetstone.sh"
out=$( cd "$PD" && printf '%s' "$EXITPM" \
       | env HOME="$HD" AETHER_GATE_DIR="$PD/.aether/hooks/gates" \
         bash "$REPO/hooks/enforce-suite.sh" 2>&1 ); rc=$?
assert_eq "0" "$rc" "the suite hook exits 0 on ExitPlanMode"
assert_contains "$out" "no critique on record" "…and the nudge reaches the user through it"

# ── 7. the suite matcher is derived, not hardcoded ──────────────────────────
# It was a literal in _json_register_suite_hook, so widening a plugin's matcher in its
# manifest did nothing — suite_owned hooks are replaced by the suite hook.
suite "the suite matcher comes from the manifests"
m=$( AETHER_REPO="$REPO" bash -c ". '$LIB'; eval \"\$(sed '/^COMMAND=/,\$d' '$CLI')\"; _suite_matcher" )
assert_eq "Bash|Write|Edit|MultiEdit|ExitPlanMode" "$m" "the union of every suite_owned matcher"
HM=$(mk)
env HOME="$HM" bash "$REPO/install.sh" --global --no-bonsai >/dev/null 2>&1
got=$(python3 - "$HM" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1] + "/.claude/settings.json"))
print(next((e["matcher"] for e in d["hooks"]["PreToolUse"]
            if any("enforce-suite" in h.get("command","") for h in e.get("hooks",[]))), ""))
PYEOF
)
assert_eq "$m" "$got" "…and that is what install registers"

# ── 8. malformed markers read as uncritiqued, never as passing ──────────────
suite "malformed critique markers"
D=$(mk)
printf '# P\nbody\n<!-- aether:critique date=x blockers=0 -->\nno sha\n<!-- /aether:critique -->\n' > "$D/nosha.md"
assert_eq "uncritiqued" "$( . "$LIB"; aether_plan_state "$D/nosha.md" )" "a marker with no sha= does not pass"
printf '# P\nbody\n' > "$D/two.md"; critique "$D/two.md"; critique "$D/two.md"
s=$( . "$LIB"; aether_plan_state "$D/two.md" )
case "$s" in critiqued|stale) pass "two markers resolve to a state, not a crash ($s)" ;;
             *) fail "two markers resolve to a state" "$s" ;; esac
printf '<!-- aether:critique sha=deadbeef -->\nonly a critique\n<!-- /aether:critique -->\n' > "$D/only.md"
s=$( . "$LIB"; aether_plan_state "$D/only.md" )
assert_eq "stale" "$s" "a file that is only a critique is stale, not current"
assert_eq "none" "$( . "$LIB"; aether_plan_state "$D/absent.md" )" "a missing file is 'none'"

# ── 9. fail-open, as every gate must ────────────────────────────────────────
# Exit 2 blocks the tool call, so a gate that dies on bad input locks the user out.
suite "fail-open"
H=$(mk); P=$(newproj)
for payload in 'not json' '' '{}' '{"tool_name":"Bash"}' \
    '{"tool_name":"Bash","tool_input":{"command":null}}' \
    '{"tool_name":"Write","tool_input":{"file_path":"src/日本.py"}}'; do
  err=$(mk)/err
  ( cd "$P" && printf '%s' "$payload" | env HOME="$H" bash "$GATE" >/dev/null 2>"$err" ); rc=$?
  if [ "$rc" = 2 ]; then fail "no payload exits 2" "payload: ${payload:0:40}"
  elif [ -s "$err" ]; then fail "no payload writes to stderr" "$(head -1 "$err")"
  fi
done
pass "6 hostile payloads: none exits 2, none writes to stderr"

# ── 10. aether plan status ──────────────────────────────────────────────────
suite "aether plan status"
H=$(mk); P=$(newproj)
out=$( cd "$P" && env HOME="$H" bash "$CLI" plan status )
assert_contains "$out" "no plan recorded" "says so when nothing is recorded"
mkdir -p "$H/.claude/plans"; A="$H/.claude/plans/a.md"; printf '# A\nbody\n' > "$A"
record "$H" "$P" "$A"
out=$( cd "$P" && env HOME="$H" bash "$CLI" plan status )
assert_contains "$out" "no critique on record" "reports uncritiqued"
assert_contains "$out" "not yet observed" "reports whether ExitPlanMode has ever fired"
critique "$A"
out=$( cd "$P" && env HOME="$H" bash "$CLI" plan status )
assert_contains "$out" "critiqued, and current" "reports critiqued"
printf '\nmore\n' >> "$A"
out=$( cd "$P" && env HOME="$H" bash "$CLI" plan status )
assert_contains "$out" "changed after its last critique" "reports stale"

# ── 11. the recorder ────────────────────────────────────────────────────────
suite "the recorder only records plans"
H=$(mk); P=$(newproj); mkdir -p "$H/.claude/plans" "$P/.claude/plans"
record "$H" "$P" "$H/.claude/plans/g.md"
[ -f "$P/.aether/out/.plan" ] && pass "a global plan is recorded" || fail "a global plan is recorded"
rm -f "$P/.aether/out/.plan"
record "$H" "$P" ".claude/plans/l.md"
[ -f "$P/.aether/out/.plan" ] && pass "a project plan is recorded" || fail "a project plan is recorded"
for path in "README.md" "src/x.py" ".claude/plans/CRITIQUE.md" ".claude/plans/TEMPER.md"; do
  rm -f "$P/.aether/out/.plan"; record "$H" "$P" "$path"
  [ -f "$P/.aether/out/.plan" ] && fail "$path is not recorded as a plan" \
                               || pass "$path is not recorded as a plan"
done
# It is project-relative, never global — the .nudged bug of v1.1.0.
[ -f "$H/.aether/out/.plan" ] && fail "the pointer never lands in HOME" \
                             || pass "the pointer never lands in HOME"

summary
