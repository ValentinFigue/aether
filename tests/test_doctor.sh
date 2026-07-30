#!/usr/bin/env bash
# tests/test_doctor.sh — `aether doctor`, `aether trust list|prune`.
#
# Every check here is tested against the state of an actual bug from v1.1.0, not a
# synthetic stand-in. The point of the command is that all of those states were
# invisible: the tool reported success and had done nothing.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

CLI="$REPO/bin/aether"

FAKE=()
mk() { local d; d=$(mktemp -d); FAKE+=("$d"); printf '%s' "$d"; }
cleanup() { for d in "${FAKE[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# The doctor reports on the current directory as well as HOME, so every run needs a
# neutral one — inside the repo it would see the repo's own .aether/.
NEUTRAL=$(mk)
dr() { local h="$1"; shift; ( cd "$NEUTRAL" && env HOME="$h" bash "$CLI" doctor "$@" 2>&1 ); }
at() { local h="$1"; shift; ( cd "$NEUTRAL" && env HOME="$h" bash "$CLI" "$@" 2>&1 ); }
fresh() { local h; h=$(mk); ( cd "$NEUTRAL" && env HOME="$h" bash "$CLI" install global --no-bonsai >/dev/null 2>&1 ); printf '%s' "$h"; }

# settings.json surgery, since every fixture needs some.
add_hook() {   # <home> <phase> <command>
  python3 - "$1" "$2" "$3" <<'PYEOF'
import json, sys
h, phase, cmd = sys.argv[1:4]
f = h + "/.claude/settings.json"
d = json.load(open(f))
d.setdefault("hooks", {}).setdefault(phase, []).append(
    {"matcher": "Bash", "hooks": [{"type": "command", "command": cmd}]})
json.dump(d, open(f, "w"), indent=2)
PYEOF
}
hook_paths() {  # <home> — one per line, prefixed OK/GONE
  python3 - "$1" <<'PYEOF'
import json, os, sys
d = json.load(open(sys.argv[1] + "/.claude/settings.json"))
for p in ("PreToolUse", "PostToolUse"):
    for e in d.get("hooks", {}).get(p, []):
        for h in e.get("hooks", []):
            c = h.get("command", "")
            print(("OK " if os.path.exists(c) else "GONE") + " " + c)
PYEOF
}

# ── the baseline that stops this becoming noise ───────────────────────────────
suite "a clean install reports nothing"
H=$(fresh)
out=$(dr "$H"); e=$?
assert_exit 0 "$e" "doctor exits 0 on a clean install"
assert_contains "$out" "No problems found." "…and says so"
case "$out" in *"✗"*) fail "no ✗ on a clean install" "$out" ;; *) pass "no ✗ on a clean install" ;; esac
case "$out" in *"!"*) fail "no ! on a clean install" "$out" ;; *) pass "no ! on a clean install" ;; esac

# ── the upgrade bug: a hook registered at a path that no longer exists ────────
# The stale-hook cleanup only ever handled PreToolUse, so upgrading left a
# PostToolUse entry aimed at ~/.local/share/aether/ and Claude Code tried to run a
# deleted script on every Bash, Write and Edit.
suite "a hook whose script is gone"
H=$(fresh)
mkdir -p "$H/.local/share/cairn"
printf 'exit 0\n' > "$H/.local/share/cairn/post-cairn.sh"
add_hook "$H" PostToolUse "$H/.local/share/cairn/post-cairn.sh"
rm "$H/.local/share/cairn/post-cairn.sh"
out=$(dr "$H" --install); e=$?
assert_exit 1 "$e" "doctor exits 1 when something is wrong"
assert_contains "$out" "is registered but does not exist" "the dangling hook is reported"
assert_contains "$out" "every matching tool call" "…with why it matters"

# The same fixture is a duplicate too, which is how it looked in the wild.
assert_contains "$out" "registered more than once" "…and the duplicate is reported"

out=$(dr "$H" --fix)
assert_contains "$out" "deregistered" "--fix deregisters it"
out=$(dr "$H" --install); e=$?
assert_exit 0 "$e" "the re-run is clean"
assert_eq "1" "$(hook_paths "$H" | grep -c 'post-cairn.sh')" "post-cairn.sh is registered exactly once"
assert_eq "0" "$(hook_paths "$H" | grep -c '^GONE')" "no hook points at a missing file"

# ── the duplicate where BOTH files exist ─────────────────────────────────────
# cairn used to install standalone into ~/.local/share/cairn/, so a machine that
# had done that ran post-cairn.sh twice — both copies present, both firing.
suite "a duplicate where both files exist"
H=$(fresh)
mkdir -p "$H/.local/share/cairn"
printf 'exit 0\n' > "$H/.local/share/cairn/post-cairn.sh"; chmod +x "$H/.local/share/cairn/post-cairn.sh"
add_hook "$H" PostToolUse "$H/.local/share/cairn/post-cairn.sh"
out=$(dr "$H" --install)
assert_contains "$out" "registered more than once" "the duplicate is reported"
out=$(dr "$H" --fix)
assert_contains "$out" "deregistered the duplicate" "--fix drops one of them"
assert_eq "1" "$(hook_paths "$H" | grep -c 'post-cairn.sh')" "one registration survives"
# The one under <root>/hooks/ is the one the engine installed, so it is the keeper.
hook_paths "$H" | grep -q "$H/.aether/hooks/plugin-hooks/post-cairn.sh" \
  && pass "--fix keeps the copy the engine installed" \
  || fail "--fix keeps the copy the engine installed" "$(hook_paths "$H")"

# ── the engine registering no MCP servers at all ─────────────────────────────
# `python3 -` reads its program from stdin, so the heredoc claimed stdin and the
# server spec never arrived: {"mcpServers": {}} and a green tick.
suite "MCP servers declared but not registered"
H=$(fresh)
sed 's/^plugins=.*/plugins=bonsai cairn temper whetstone/' "$H/.aether/manifest" > "$H/.aether/manifest.new"
mv "$H/.aether/manifest.new" "$H/.aether/manifest"
printf '{\n  "mcpServers": {}\n}\n' > "$H/.claude.json"
out=$(dr "$H" --install)
assert_contains "$out" "bonsai-py is not registered" "an unregistered server is reported"
assert_contains "$out" "bonsai-ts is not registered" "…both of them"
assert_contains "$out" "but bonsai is installed"     "…and why that is wrong"

# A server registered with an empty command is worse than none — Claude Code
# would try to launch it.
H=$(fresh)
sed 's/^plugins=.*/plugins=bonsai cairn temper whetstone/' "$H/.aether/manifest" > "$H/.aether/manifest.new"
mv "$H/.aether/manifest.new" "$H/.aether/manifest"
printf '{"mcpServers":{"bonsai-py":{"type":"stdio","command":"","args":[]},"bonsai-ts":{"type":"stdio","command":"","args":[]}}}\n' > "$H/.claude.json"
assert_contains "$(dr "$H" --install)" "empty command" "an empty command is reported"

# ── a moved clone ────────────────────────────────────────────────────────────
# bonsai's MCP servers reference the clone by absolute path, and `aether update`
# re-runs from it, so a moved clone breaks both — silently.
suite "a moved clone"
H=$(fresh)
sed 's|^repo=.*|repo=/nonexistent/aether-clone|' "$H/.aether/manifest" > "$H/.aether/manifest.new"
mv "$H/.aether/manifest.new" "$H/.aether/manifest"
out=$(dr "$H" --install); e=$?
assert_exit 1 "$e" "a missing clone is a problem, not a warning"
assert_contains "$out" "the recorded clone is gone" "the missing clone is reported"
assert_contains "$out" "aether update needs it"     "…with what it breaks"

# ── a command from before the rename, still in the palette ───────────────────
suite "a stale command still in the palette"
H=$(fresh)
printf 'stale\n' > "$H/.claude/commands/autocritic.md"
printf 'stale\n' > "$H/.claude/commands/cairn-commit.md"
out=$(dr "$H" --install)
assert_contains "$out" "still in the palette" "stale commands are reported"
assert_contains "$out" "autocritic.md"        "…by name"

# ── a machine that never migrated ────────────────────────────────────────────
suite "the pre-1.0 layout still on disk"
H=$(fresh)
mkdir -p "$H/.local/share/aether"
printf 'auto_nudge_lines: 400\n' > "$H/.claude/temper.config"
out=$(dr "$H" --install)
assert_contains "$out" "pre-1.0 layout is still on disk" "leftovers are reported"
assert_contains "$out" "aether migrate"                  "…pointing at the fix"

# ── a gate that does not parse ───────────────────────────────────────────────
# A corrupt gate is silently skipped by the dispatcher, by design — the
# alternative locks the user out of every tool call. So something has to say so.
suite "a gate that fails to parse"
H=$(fresh)
printf 'gate_cairn() { if [ \n' > "$H/.aether/hooks/gates/enforce-cairn.sh"
out=$(dr "$H" --install)
assert_contains "$out" "fail to parse" "the broken gate is reported"
assert_contains "$out" "enforce-cairn.sh" "…by name"

# ── permissions ──────────────────────────────────────────────────────────────
suite "permissions missing from settings.json"
H=$(fresh)
python3 - "$H" <<'PYEOF'
import json, sys
f = sys.argv[1] + "/.claude/settings.json"
d = json.load(open(f))
d.setdefault("permissions", {})["allow"] = ["Read"]
json.dump(d, open(f, "w"), indent=2)
PYEOF
out=$(dr "$H" --install)
assert_contains "$out" "permissions missing" "missing permissions are reported"
assert_contains "$out" "Bash" "…naming which"

# ── trust ────────────────────────────────────────────────────────────────────
# Entries accumulated for every project ever trusted and nothing pruned them, so a
# path deleted months ago still granted consent if a directory reappeared there.
suite "trust list and prune"
H=$(fresh)
P1=$(mk); P2=$(mk); P3=$(mk)
for d in "$P1" "$P2" "$P3"; do
  mkdir -p "$d/.aether"; printf '[project]\ntest: echo hi\n' > "$d/.aether/config"
  ( cd "$d" && env HOME="$H" bash "$CLI" trust >/dev/null 2>&1 )
done
printf 'lint: edited by hand\n' >> "$P2/.aether/config"     # → changed
rm -rf "$P3"                                                # → dead

out=$(at "$H" trust list)
assert_contains "$out" "ok " "trust list shows an unchanged project"
assert_contains "$out" "changed" "…one edited since"
assert_contains "$out" "dead"    "…and one whose directory is gone"

out=$(dr "$H" --config)
assert_contains "$out" "no longer exists" "doctor reports the dead entry"
assert_contains "$out" "aether trust prune" "…with the fix"
assert_contains "$out" "edited since being trusted" "…and the changed one separately"

out=$(at "$H" trust prune)
assert_contains "$out" "removed 1" "prune removes exactly the dead one"
out=$(at "$H" trust list)
case "$out" in *dead*) fail "the dead entry is gone" "$out" ;; *) pass "the dead entry is gone" ;; esac
assert_contains "$out" "$P1" "the unchanged project survives"
assert_contains "$out" "$P2" "…and so does the edited one"
# Trust still functions after pruning.
assert_eq "echo hi" "$( cd "$P1" && env HOME="$H" bash "$CLI" config get project.test )" \
  "a surviving entry still grants trust"

out=$(at "$H" trust prune)
assert_contains "$out" "nothing to prune" "pruning twice is a no-op"

# ── --fix must be inert when there is nothing to fix ─────────────────────────
# It used to back up settings.json unconditionally, so every run left a new .bak.
suite "--fix changes nothing when there is nothing to fix"
H=$(fresh)
snap() { ( cd "$H" && find . | sort | while IFS= read -r f; do
  if [ -f "$f" ]; then printf '%s %s\n' "$( (md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1) )" "$f"
  else printf 'dir %s\n' "$f"; fi; done ); }
before=$(snap)
out=$(dr "$H" --fix)
assert_contains "$out" "nothing to fix" "it says there is nothing to do"
assert_eq "$before" "$(snap)" "the home directory is byte-identical, .bak included"

# ── `aether config doctor` still works, as the config half ──────────────────
# It shipped one release ago and is documented, so it must keep working — but as a
# call into the same implementation, not a second copy.
suite "config doctor is the config half"
H=$(fresh); PJ=$(mk); mkdir -p "$PJ/.aether"
printf '[temper]\nauto_nudge_line: 400\n' > "$PJ/.aether/config"
out=$( cd "$PJ" && env HOME="$H" bash "$CLI" config doctor 2>&1 )
assert_contains "$out" "unknown key" "config doctor still reports a typo"
case "$out" in
  *"suite hook"*|*"manifest entries"*) fail "config doctor does not check the install" "$out" ;;
  *) pass "config doctor does not check the install" ;;
esac
out=$( cd "$PJ" && env HOME="$H" bash "$CLI" doctor 2>&1 )
assert_contains "$out" "unknown key"        "doctor includes the config checks"
assert_contains "$out" "manifest entries"   "…and the install checks"
n=$(printf '%s' "$out" | grep -c 'unknown key' || true)
assert_eq "1" "$n" "the config check runs once, not once per half"

# ── all three JSON backends agree ────────────────────────────────────────────
suite "backend equivalence"
H=$(fresh)
mkdir -p "$H/.local/share/cairn"
add_hook "$H" PostToolUse "$H/.local/share/cairn/post-cairn.sh"
ref=""
for b in python3 node jq; do
  command -v "$b" >/dev/null 2>&1 || continue
  got=$( cd "$NEUTRAL" && env HOME="$H" AETHER_JSON_BACKEND="$b" bash "$CLI" doctor --install 2>&1 \
         | grep -cE '^  (✗|!)' || true )
  if [ -z "$ref" ]; then ref="$got"; pass "$b: $got finding(s)"
  else assert_eq "$ref" "$got" "$b reports the same count as python3"; fi
done

summary
