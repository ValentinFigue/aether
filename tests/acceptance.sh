#!/usr/bin/env bash
# tests/acceptance.sh — end-to-end checks against a throwaway HOME.
#
#   bash tests/acceptance.sh              # everything except the slowest
#   bash tests/acceptance.sh --full       # also build bonsai and handshake its servers
#   bash tests/acceptance.sh --perf-only  # just the hook cost
#
# This is not the unit suite. `tests/run.sh` asserts behaviour; this exercises the
# things that only show up in a real install: paths with spaces, hostile hook
# input, upgrading from a released tag, repeated installs, and what the hook costs
# on every tool call.
#
# It never writes to your real HOME. Every check runs against a temporary one, and
# the only thing it reads from your machine is the git history of this clone.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO" || exit 1

MODE=all
case "${1:-}" in
  --full)      MODE=full ;;
  --perf-only) MODE=perf ;;
  --help|-h)   sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "")          ;;
  *)           printf 'Unknown option: %s (try --help)\n' "$1" >&2; exit 1 ;;
esac

PASS=0; FAIL=0; WARN=0
TMPS=()
mk() { local d; d=$(mktemp -d); TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

grp()  { printf '\n\033[1m── %s ──\033[0m\n' "$1"; }
ok()   { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
warn() { WARN=$((WARN+1)); printf '  \033[33m!\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
note() { printf '    %s\n' "$1"; }

# Milliseconds. python3 is already a hard requirement of every hook, and macOS
# has neither `date +%N` nor bash 5's EPOCHREALTIME.
now_ms() { python3 -c 'import time;print(int(time.time()*1000))'; }

PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"ls"}}'

# ── 1. syntax and lint ───────────────────────────────────────────────────────
if [ "$MODE" != perf ]; then
grp "syntax"
bad_files=""
while IFS= read -r f; do
  bash -n "$f" 2>/dev/null || bad_files="$bad_files $f"
done < <(git ls-files '*.sh' 'bin/*' 'plugins/*/bin/*' 2>/dev/null)
[ -z "$bad_files" ] && ok "every tracked script parses" || bad "every tracked script parses" "$bad_files"

if command -v shellcheck >/dev/null 2>&1; then
  n=$(git ls-files '*.sh' 'bin/*' 'plugins/*/bin/*' | xargs shellcheck --severity=error --shell=bash 2>&1 | grep -c '^In ' || true)
  [ "$n" -eq 0 ] && ok "shellcheck --severity=error is clean" \
                 || bad "shellcheck --severity=error is clean" "$n file(s) with errors"
else
  warn "shellcheck is not installed — CI runs it" "brew install shellcheck"
fi

# ── 2. the unit suite ────────────────────────────────────────────────────────
grp "unit suite"
log=$(mk)/suite.log
if bash tests/run.sh > "$log" 2>&1; then
  ok "tests/run.sh passed ($(grep -cE '^  ✓' "$log") assertions)"
else
  bad "tests/run.sh passed" "$(grep -E '^  ✗' "$log" | head -5)"
  note "full output: $log"
fi

# ── 3. a path containing spaces ──────────────────────────────────────────────
# Unquoted expansions survive every test whose paths have no spaces in them.
grp "paths containing spaces"
H="$(mk)/home dir with spaces"; mkdir -p "$H"
if env HOME="$H" bash install.sh --global --no-bonsai >/dev/null 2>&1; then
  ok "install exits 0"
else
  bad "install exits 0"
fi
[ -x "$H/.aether/hooks/enforce-suite.sh" ] && ok "the hook landed and is executable" \
                                           || bad "the hook landed and is executable"
hp=$(python3 - "$H" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1] + "/.claude/settings.json"))
print(d["hooks"]["PreToolUse"][0]["hooks"][0]["command"])
PY
)
[ -n "$hp" ] && [ -f "$hp" ] && ok "the path registered in settings.json resolves" \
                            || bad "the path registered in settings.json resolves" "${hp:-not registered}"
out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' \
      | env HOME="$H" bash "$hp" 2>&1)
case "$out" in *Cairn*) ok "a gate fires from a spaced path" ;;
               *) bad "a gate fires from a spaced path" "${out:0:70}" ;; esac
env HOME="$H" bash uninstall.sh --global >/dev/null 2>&1
[ -e "$H/.aether/hooks/enforce-suite.sh" ] && bad "uninstall removed the hook" \
                                          || ok "uninstall removed the hook"

# ── 4. hostile hook input ────────────────────────────────────────────────────
# The value that matters is exit 2: Claude Code reads it as "block this tool
# call", so a gate that dies on bad input would lock the user out of everything.
grp "hostile hook input"
HG=$(mk); env HOME="$HG" bash install.sh --global --no-bonsai >/dev/null 2>&1
HOOK="$HG/.aether/hooks/enforce-suite.sh"
big=$(python3 -c 'print("{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m \\\"" + "x"*200000 + "\\\"\"}}")')
i=0
for j in \
  'not json at all' \
  '' \
  '{}' \
  '{"tool_input":{"command":"git push"}}' \
  '{"tool_name":"Bash","tool_input":{"command":null}}' \
  '{"tool_name":"Bash","tool_input":{}}' \
  '{"tool_name":"Write","tool_input":{"file_path":"src/日本語.py"}}' \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"a'"'"'b\\\"c\""}}' \
  "$big"; do
  i=$((i+1))
  err=$(mk)/err
  printf '%s' "$j" | env HOME="$HG" bash "$HOOK" >/dev/null 2>"$err"; rc=$?
  if [ "$rc" = 2 ]; then bad "input #$i does not exit 2" "exit 2 blocks the tool call"
  elif [ -s "$err" ]; then bad "input #$i writes nothing to stderr" "$(head -1 "$err")"
  else PASS=$((PASS+1)); fi
done
ok "9 hostile inputs: none exits 2, none writes to stderr"

# ── 5. --dry-run is inert ────────────────────────────────────────────────────
# It has regressed three times: once when the installers became wrappers, once
# when config seeding and migration arrived, and once by claiming work it had not
# done. Bonsai is included on purpose — its build is the part that escaped before.
grp "--dry-run"
HD=$(mk); mkdir -p "$HD/.claude"
printf 'auto_nudge_lines: 999\n' > "$HD/.claude/temper.config"   # something to migrate
snap() { ( cd "$HD" && find . | sort ); }
before=$(snap)
out=$(env HOME="$HD" bash install.sh --global --claude-md --dry-run 2>&1)
[ "$before" = "$(snap)" ] && ok "creates no file and no directory, bonsai included" \
                          || bad "creates no file and no directory" "$(diff <(printf '%s\n' "$before") <(snap) | head -4)"
case "$out" in *"✓"*) bad "prints no ✓ (it did nothing to tick)" ;; *) ok "prints no ✓ (it did nothing to tick)" ;; esac
[ -f "$HD/.claude/temper.config" ] && ok "does not migrate" || bad "does not migrate"

# ── 6. idempotence ───────────────────────────────────────────────────────────
grp "repeated installs"
HI=$(mk); mkdir -p "$HI/.claude"
printf '# my own notes\n\nBe careful.\n' > "$HI/.claude/CLAUDE.md"
hashall() { ( cd "$HI" && find . -type f | sort | while IFS= read -r f; do
    printf '%s %s\n' "$( (md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1) )" "$f"; done ); }
for _ in 1 2 3; do env HOME="$HI" bash install.sh --global --claude-md --no-bonsai >/dev/null 2>&1; done
a=$(hashall)
env HOME="$HI" bash install.sh --global --claude-md --no-bonsai >/dev/null 2>&1
[ "$a" = "$(hashall)" ] && ok "a fourth install changes nothing" \
                        || bad "a fourth install changes nothing" "$(diff <(printf '%s\n' "$a") <(hashall) | head -4)"
n=$(grep -c 'aether:start' "$HI/.claude/CLAUDE.md" 2>/dev/null || true)
[ "$n" = 1 ] && ok "the CLAUDE.md block appears exactly once" \
             || bad "the CLAUDE.md block appears exactly once" "found $n"
grep -q '^# my own notes$' "$HI/.claude/CLAUDE.md" && ok "your own CLAUDE.md content is untouched" \
                                                  || bad "your own CLAUDE.md content is untouched"
n=$(python3 - "$HI" <<'PY' 2>/dev/null
import json, os, sys
d = json.load(open(sys.argv[1] + "/.claude/settings.json"))
print(sum(1 for p in ("PreToolUse","PostToolUse")
            for e in d.get("hooks",{}).get(p,[]) for h in e.get("hooks",[])
            if not os.path.exists(h.get("command",""))))
PY
)
[ "${n:-0}" = 0 ] && ok "no hook points at a missing script" || bad "no hook points at a missing script" "$n dangling"
[ -z "$(cd "$HI" && find . -name '*aether-tmp*')" ] && ok "no temp file left behind" || bad "no temp file left behind"

# ── 6b. the doctor agrees the install is sound ───────────────────────────────
# The strongest single check available: it compares every artefact against what the
# manifests declare, so a clean install that it complains about means one of the two
# is wrong.
grp "aether doctor after a fresh install"
HDR=$(mk); NEUTRAL_D=$(mk)
env HOME="$HDR" bash install.sh --global --no-bonsai >/dev/null 2>&1
out=$( cd "$NEUTRAL_D" && env HOME="$HDR" bash "$REPO/bin/aether" doctor 2>&1 ); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$(printf '%s' "$out" | grep -E '^  (✗|!)')" ]; then
  ok "reports nothing on a fresh install"
else
  bad "reports nothing on a fresh install" "$(printf '%s' "$out" | grep -E '^  (✗|!)' | head -4)"
fi
snapd() { ( cd "$HDR" && find . | sort ); }
b4=$(snapd)
( cd "$NEUTRAL_D" && env HOME="$HDR" bash "$REPO/bin/aether" doctor --fix >/dev/null 2>&1 )
[ "$b4" = "$(snapd)" ] && ok "--fix changes nothing when there is nothing to fix" \
                       || bad "--fix changes nothing when there is nothing to fix"

# ── 6c. the plan flow, on a real install ─────────────────────────────────────
# The gate had never seen a plan written by plan mode, because it globbed the project
# plans directory and plan mode writes to ~/.claude/plans/. This is that end to end,
# through an actual install rather than by calling the gate directly.
grp "the plan flow after a real install"
HPL=$(mk); PPL=$(mk)
env HOME="$HPL" bash install.sh --global --no-bonsai >/dev/null 2>&1
mkdir -p "$HPL/.claude/plans" "$PPL/src"
( cd "$PPL" && git init -q . && git config user.email t@t && git config user.name t )
PLAN="$HPL/.claude/plans/acceptance.md"
printf '# A plan\n\nDo the thing.\n' > "$PLAN"

# The registered matcher must cover ExitPlanMode, or the trigger can never fire.
m=$(python3 - "$HPL" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1] + "/.claude/settings.json"))
print(next((e["matcher"] for e in d["hooks"]["PreToolUse"]
            if any("enforce-suite" in h.get("command","") for h in e.get("hooks",[]))), ""))
PYEOF
)
case "$m" in *ExitPlanMode*) ok "the installed matcher covers ExitPlanMode ($m)" ;;
             *) bad "the installed matcher covers ExitPlanMode" "got: $m" ;; esac

# The PostToolUse recorder is registered and records the plan.
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$PLAN" \
  | ( cd "$PPL" && env HOME="$HPL" bash "$HPL/.aether/hooks/plugin-hooks/post-whetstone.sh" ) >/dev/null 2>&1
got=$( cd "$PPL" && env HOME="$HPL" bash "$HPL/.local/bin/aether" plan path 2>/dev/null )
[ "$got" = "$PLAN" ] && ok "the recorder pointed the gate at the plan-mode plan" \
                     || bad "the recorder pointed the gate at the plan-mode plan" "got: ${got:-nothing}"

# Uncritiqued: the suite hook nudges at commit and never exits 2.
out=$( cd "$PPL" && printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' \
       | env HOME="$HPL" bash "$HPL/.aether/hooks/enforce-suite.sh" 2>&1 ); rc=$?
case "$rc$out" in
  1*Whetstone*) ok "an uncritiqued plan nudges through the suite hook" ;;
  2*) bad "the gate never exits 2" "exit 2 blocks the tool call" ;;
  *) bad "an uncritiqued plan nudges through the suite hook" "exit=$rc out=${out:0:60}" ;;
esac

# ExitPlanMode prints but must never gate.
out=$( cd "$PPL" && printf '{"tool_name":"ExitPlanMode","tool_input":{}}' \
       | env HOME="$HPL" bash "$HPL/.aether/hooks/enforce-suite.sh" 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && ok "ExitPlanMode is never gated (exit 0)" \
               || bad "ExitPlanMode is never gated" "exit=$rc"
case "$out" in *Whetstone*) ok "…and still says the plan is uncritiqued" ;;
               *) bad "…and still says the plan is uncritiqued" "${out:0:60}" ;; esac

# Critique it in place, the way /critique-plan is told to, and everything goes quiet.
h=$( . "$REPO/hooks/aether-config.sh"; aether_plan_hash "$PLAN" )
printf '\n<!-- aether:critique sha=%s date=2026-07-30 blockers=0 -->\n## Critique\nfine\n<!-- /aether:critique -->\n' \
  "$h" >> "$PLAN"
out=$( cd "$PPL" && printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' \
       | env HOME="$HPL" bash "$HPL/.aether/hooks/enforce-suite.sh" 2>&1 ); rc=$?
# cairn also nudges here, about the weak commit message — correct and unrelated. The
# claim is about whetstone, so assert about whetstone rather than the combined exit.
case "$out" in
  *Whetstone*) bad "a critique inside the plan silences whetstone" "${out:0:70}" ;;
  *) ok "a critique inside the plan silences whetstone" ;;
esac

# ── 7. upgrading from the last release ───────────────────────────────────────
grp "upgrade from $(git describe --tags --abbrev=0 2>/dev/null || echo 'the previous release')"
tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -z "$tag" ]; then
  warn "no tag to upgrade from — skipped"
else
  OLD=$(mk); git archive "$tag" 2>/dev/null | tar -x -C "$OLD" && {
    HU=$(mk)
    ( cd "$OLD" && env HOME="$HU" bash install.sh --global --no-bonsai >/dev/null 2>&1 )
    printf 'auto_nudge_lines: 777\nseverity: red\n' > "$HU/.claude/temper.config"
    env HOME="$HU" bash install.sh --global --no-bonsai >/dev/null 2>&1
    [ -f "$HU/.aether/config" ] && ok "the old config migrated into .aether/config" \
                                || bad "the old config migrated into .aether/config"
    v=$(env HOME="$HU" bash bin/aether config get temper.auto_nudge_lines 2>/dev/null)
    [ "$v" = 777 ] && ok "the migrated value survives (777)" || bad "the migrated value survives" "got [$v]"
    [ -f "$HU/.claude/temper.config.bak" ] && ok "the old file is backed up" || bad "the old file is backed up"
    [ -e "$HU/.local/share/aether" ] && bad "the retired directory is gone" \
                                     || ok "the retired directory is gone"
    n=$(python3 - "$HU" <<'PY' 2>/dev/null
import json, os, sys
d = json.load(open(sys.argv[1] + "/.claude/settings.json"))
print(sum(1 for p in ("PreToolUse","PostToolUse")
            for e in d.get("hooks",{}).get(p,[]) for h in e.get("hooks",[])
            if not os.path.exists(h.get("command",""))))
PY
)
    [ "${n:-0}" = 0 ] && ok "the upgrade leaves no dangling hook" || bad "the upgrade leaves no dangling hook" "$n"
    # And the doctor must agree, which is the check that would have caught the
    # dangling PostToolUse entry this upgrade path used to leave behind.
    NEUTRAL_U=$(mk)
    dout=$( cd "$NEUTRAL_U" && env HOME="$HU" bash "$REPO/bin/aether" doctor --install 2>&1 ); drc=$?
    if [ "$drc" -eq 0 ] && [ -z "$(printf '%s' "$dout" | grep -E '^  ✗')" ]; then
      ok "aether doctor is clean after the upgrade"
    else
      bad "aether doctor is clean after the upgrade" "$(printf '%s' "$dout" | grep -E '^  ✗' | head -3)"
    fi
  } || warn "could not export $tag — skipped"
fi
fi   # MODE != perf

# ── 8. what the hook costs ───────────────────────────────────────────────────
# It runs on every Bash, Write, Edit and MultiEdit call, so this is latency you
# pay all day. Measured against the last release as a reference rather than an
# absolute budget, because the number depends on the machine.
grp "hook cost"
HP=$(mk); env HOME="$HP" bash install.sh --global --no-bonsai >/dev/null 2>&1
bench() {
  local s e; s=$(now_ms)
  for _ in $(seq 1 20); do printf '%s' "$PAYLOAD" | env HOME="$2" bash "$1" >/dev/null 2>&1; done
  e=$(now_ms); printf '%s' $(( (e - s) / 20 ))
}
here=$(bench "$HP/.aether/hooks/enforce-suite.sh" "$HP")
note "this build: ${here}ms per tool call"
tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -n "$tag" ]; then
  OLD2=$(mk); HO=$(mk)
  if git archive "$tag" 2>/dev/null | tar -x -C "$OLD2"; then
    ( cd "$OLD2" && env HOME="$HO" bash install.sh --global --no-bonsai >/dev/null 2>&1 )
    ref=""
    for c in "$HO/.aether/hooks/enforce-suite.sh" "$HO/.local/share/aether/enforce-suite.sh"; do
      [ -f "$c" ] && ref="$c" && break
    done
    if [ -n "$ref" ]; then
      was=$(bench "$ref" "$HO")
      note "$tag:       ${was}ms per tool call"
      if [ "$here" -le $(( was + 15 )) ]; then ok "no more than 15ms slower than $tag"
      else warn "$(( here - was ))ms slower than $tag" "acceptable if deliberate; investigate if not"; fi
    else warn "could not install $tag to compare against"; fi
  fi
fi
n=$(printf '%s' "$PAYLOAD" | env HOME="$HP" bash -x "$HP/.aether/hooks/enforce-suite.sh" 2>&1 >/dev/null | grep -c '+ awk' || true)
[ "${n:-0}" -le 3 ] && ok "at most 3 awk processes per tool call (saw $n)" \
                    || bad "at most 3 awk processes per tool call" "saw $n — the per-key path is back"

# ── 9. bonsai, end to end ────────────────────────────────────────────────────
if [ "$MODE" = full ]; then
grp "bonsai (--full)"
HB=$(mk)
if env HOME="$HB" bash install.sh --global >/dev/null 2>&1; then
  ok "install with bonsai exits 0"
else
  bad "install with bonsai exits 0" "needs uv, node and npm"
fi
srv=$(python3 - "$HB" <<'PY' 2>/dev/null
import json, sys
try: d = json.load(open(sys.argv[1] + "/.claude.json"))
except Exception: print(""); raise SystemExit
print(" ".join(sorted(d.get("mcpServers", {}))))
PY
)
[ "$srv" = "bonsai-py bonsai-ts" ] && ok "both MCP servers are registered" \
                                  || bad "both MCP servers are registered" "got [${srv:-none}]"
handshake() {
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | "$@" 2>/dev/null | python3 -c '
import sys, json
for l in sys.stdin:
    try: m = json.loads(l)
    except Exception: continue
    if m.get("id") == 2: print(len(m["result"]["tools"])); break
'
}
for pair in "bonsai-py 8" "bonsai-ts 5"; do
  set -- $pair
  spec=$(python3 - "$HB" "$1" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1] + "/.claude.json"))["mcpServers"][sys.argv[2]]
print(d["command"], " ".join(d["args"]))
PY
)
  got=$(handshake $spec)
  [ "${got:-0}" -ge "$2" ] && ok "$1 answers a handshake ($got tools)" \
                           || bad "$1 answers a handshake" "expected ≥$2, got ${got:-no response}"
done
NEUTRAL_B=$(mk)
out=$( cd "$NEUTRAL_B" && env HOME="$HB" bash "$REPO/bin/aether" doctor --install --deep 2>&1 )
case "$out" in
  *"answers tools/list"*) ok "aether doctor --deep handshakes them too" ;;
  *) bad "aether doctor --deep handshakes them too" "$(printf '%s' "$out" | grep -E 'MCP' | head -3)" ;;
esac
fi

# ── summary ──────────────────────────────────────────────────────────────────
printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32m%s passed\033[0m' "$PASS"
  [ "$WARN" -gt 0 ] && printf ', \033[33m%s warning(s)\033[0m' "$WARN"
  printf '\n'
  [ "$MODE" = all ] && printf 'Run with --full to build bonsai and handshake its MCP servers.\n'
  exit 0
fi
printf '\033[31m%s failed\033[0m, %s passed' "$FAIL" "$PASS"
[ "$WARN" -gt 0 ] && printf ', %s warning(s)' "$WARN"
printf '\n'
exit 1
