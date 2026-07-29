#!/usr/bin/env bash
# tests/test_cli.sh — the aether CLI and the uninstall wrapper.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

CLI="$REPO/bin/aether"

FAKE_HOMES=()
new_home() { local h; h=$(mktemp -d); FAKE_HOMES+=("$h"); printf '%s' "$h"; }
cleanup() { for h in "${FAKE_HOMES[@]}"; do rm -rf "$h"; done; }
trap cleanup EXIT

jsonq() { python3 -c "$2" "$1" 2>/dev/null; }

# ── basics ───────────────────────────────────────────────────────────────────
suite "basics"
out=$(bash "$CLI" version 2>&1); e=$?
assert_exit 0 "$e" "aether version exits 0"
assert_contains "$out" "1.0.0" "aether version reports 1.0.0"

out=$(bash "$CLI" help 2>&1); e=$?
assert_exit 0 "$e" "aether help exits 0"
assert_contains "$out" "aether update" "help documents update"
assert_contains "$out" "aether version" "help documents version"

out=$(bash "$CLI" nonsense 2>&1); e=$?
assert_exit 1 "$e" "unknown subcommand exits 1"

# ── status against a real install ────────────────────────────────────────────
suite "status"
H=$(new_home)
env HOME="$H" bash "$REPO/install.sh" --global --no-bonsai >/dev/null 2>&1
out=$(env HOME="$H" bash "$CLI" status 2>&1); e=$?
assert_exit 0 "$e" "status exits 0"
assert_contains "$out" "enforce-suite.sh registered" "status sees the registered hook"
assert_contains "$out" "Gates:" "status reports the gates directory"
assert_contains "$out" "3 loaded" "status counts the three installed gates"
assert_contains "$out" "Clone:" "status reports the clone path"
assert_contains "$out" "$REPO" "status resolves the clone to this checkout"
assert_contains "$out" "Installed version: 1.0.0" "status reports the installed version"

# ── enable / disable ─────────────────────────────────────────────────────────
suite "enable / disable"
env HOME="$H" bash "$CLI" disable global >/dev/null 2>&1
out=$(env HOME="$H" bash "$CLI" status 2>&1)
n=$(printf '%s' "$out" | grep -c 'disabled' || true)
assert_eq "4" "$n" "disable global marks all four plugins disabled"

# a disabled plugin's gate must actually stop firing
FIX=$(mktemp -d); cd "$FIX" || exit 1
git init -q .; git config user.email t@t; git config user.name t
printf 'x\n' > f.txt; git add f.txt; git commit -qm init
out=$(payload Bash 'git commit -m wip' | env HOME="$H" bash "$H/.local/share/aether/enforce-suite.sh" 2>&1); e=$?
case "$out" in
  *"Cairn nudge"*) fail "disabling cairn silences its gate at runtime" "cairn still fired" ;;
  *) pass "disabling cairn silences its gate at runtime" ;;
esac
cd "$REPO" || exit 1; rm -rf "$FIX"

env HOME="$H" bash "$CLI" enable global >/dev/null 2>&1
out=$(env HOME="$H" bash "$CLI" status 2>&1)
n=$(printf '%s' "$out" | grep -c 'enabled' || true)
assert_eq "4" "$n" "enable global marks all four plugins enabled"

# ── update error paths ───────────────────────────────────────────────────────
# update is a git pull plus a re-run of the local installer, so it has to fail
# clearly when the recorded clone is missing rather than half-updating.
suite "update error paths"
H2=$(new_home)
mkdir -p "$H2/.claude"
printf 'version=1.0.0\nscope=global\n' > "$H2/.claude/aether.manifest"
out=$(env HOME="$H2" bash "$CLI" update 2>&1); e=$?
assert_exit 1 "$e" "update fails when the manifest has no repo="
assert_contains "$out" "predates aether 1.0.0" "update explains a pre-1.0.0 manifest"

printf 'version=1.0.0\nscope=global\nrepo=/nonexistent/aether\n' > "$H2/.claude/aether.manifest"
out=$(env HOME="$H2" bash "$CLI" update 2>&1); e=$?
assert_exit 1 "$e" "update fails when the recorded clone is gone"
assert_contains "$out" "no longer there" "update names the missing clone"

# ── plugin update honours the recorded scope ─────────────────────────────────
# All three plugin CLIs used to run `install.sh global` regardless of scope=, so
# updating a local install silently wrote a global one into ~/.claude. Same bug
# as `aether uninstall` had, in three more places.
suite "plugin update respects scope"
HU=$(new_home)
PROJ_U=$(mktemp -d)
cd "$PROJ_U" || exit 1
env HOME="$HU" bash "$REPO/install.sh" --no-bonsai >/dev/null 2>&1   # LOCAL install
[ -f .claude/commands/draft-commit.md ] && pass "local install put commands in the project" \
                                        || fail "local install put commands in the project"
before=$(ls "$HU/.claude/commands" 2>/dev/null | wc -l | tr -d ' ')

for p in cairn temper whetstone; do
  env HOME="$HU" bash "$REPO/plugins/$p/bin/$p" update >/dev/null 2>&1 || true
done

after=$(ls "$HU/.claude/commands" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$before" "$after" "updating a local install writes nothing to the global commands dir"
[ -f .claude/commands/draft-commit.md ] && pass "the local install is still intact after update" \
                                        || fail "the local install is still intact after update"
cd "$REPO" || exit 1
rm -rf "$PROJ_U"

# ── uninstall ────────────────────────────────────────────────────────────────
suite "uninstall"
H3=$(new_home)
env HOME="$H3" bash "$REPO/install.sh" --global --claude-md --no-bonsai >/dev/null 2>&1
S="$H3/.claude/settings.json"
[ -f "$H3/.local/share/aether/gates/enforce-cairn.sh" ] \
  && pass "gates present before uninstall" || fail "gates present before uninstall"

env HOME="$H3" bash "$REPO/uninstall.sh" --global --claude-md >"$H3/un.log" 2>&1; e=$?
assert_exit 0 "$e" "uninstall.sh wrapper exits 0"

[ -e "$H3/.local/share/aether/enforce-suite.sh" ] \
  && fail "uninstall removes enforce-suite.sh" || pass "uninstall removes enforce-suite.sh"
[ -e "$H3/.local/share/aether/gates" ] \
  && fail "uninstall removes the gates directory" || pass "uninstall removes the gates directory"
[ -e "$H3/.local/bin/aether" ] \
  && fail "uninstall removes the CLI" || pass "uninstall removes the CLI"
[ -e "$H3/.claude/aether.manifest" ] \
  && fail "uninstall removes the manifest" || pass "uninstall removes the manifest"

pre=$(jsonq "$S" '
import json,sys
s=json.load(open(sys.argv[1]))
print("\n".join(h.get("command","") for e in s.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[])))')
case "$pre" in
  *enforce-suite*) fail "uninstall deregisters the PreToolUse hook" "still present" ;;
  *) pass "uninstall deregisters the PreToolUse hook" ;;
esac

# The plugins stay installed for standalone use, so their PostToolUse hook and
# their slash commands must survive an aether uninstall.
post=$(jsonq "$S" '
import json,sys
s=json.load(open(sys.argv[1]))
print("\n".join(h.get("command","") for e in s.get("hooks",{}).get("PostToolUse",[]) for h in e.get("hooks",[])))')
assert_contains "$post" "post-cairn.sh" "uninstall leaves post-cairn.sh registered"
[ -f "$H3/.claude/commands/draft-commit.md" ] \
  && pass "uninstall leaves plugin slash commands in place" \
  || fail "uninstall leaves plugin slash commands in place"

n=$(grep -c '<!-- aether:start -->' "$H3/.claude/CLAUDE.md" 2>/dev/null || true)
assert_eq "0" "$n" "--claude-md strips the aether block"
[ -f "$S.bak" ] && pass "uninstall backs up settings.json first" \
                || fail "uninstall backs up settings.json first"

# ── local uninstall ──────────────────────────────────────────────────────────
# Local mode puts the hook, gates, CLI and manifest inside the project rather
# than under $HOME. cmd_uninstall hardcoded the global paths regardless of
# scope, so a local uninstall removed none of them and deleted the *global*
# manifest instead, breaking `aether update` for an unrelated global install.
suite "local uninstall"
H4=$(new_home)
PROJ=$(mktemp -d)
cd "$PROJ" || exit 1
env HOME="$H4" bash "$REPO/install.sh" --no-bonsai --claude-md >/dev/null 2>&1

for p in .claude/hooks/enforce-suite.sh .claude/hooks/gates .bin/aether .claude/aether.manifest; do
  [ -e "$p" ] && pass "local install created $p" || fail "local install created $p"
done

# A global install that must be left completely alone.
mkdir -p "$H4/.claude"
printf 'version=1.0.0\nscope=global\nrepo=/elsewhere/aether\n' > "$H4/.claude/aether.manifest"

env HOME="$H4" bash "$REPO/uninstall.sh" --claude-md >/dev/null 2>&1
e=$?
assert_exit 0 "$e" "local uninstall exits 0"

for p in .claude/hooks/enforce-suite.sh .claude/hooks/gates .bin/aether .claude/aether.manifest; do
  [ -e "$p" ] && fail "local uninstall removed $p" || pass "local uninstall removed $p"
done
[ -d .claude/hooks ] && fail "empty .claude/hooks/ is tidied away" || pass "empty .claude/hooks/ is tidied away"
[ -d .bin ]          && fail "empty .bin/ is tidied away"          || pass "empty .bin/ is tidied away"

[ -f "$H4/.claude/aether.manifest" ] \
  && pass "a local uninstall leaves the global manifest alone" \
  || fail "a local uninstall leaves the global manifest alone"

[ -f .claude/commands/draft-commit.md ] \
  && pass "local uninstall leaves the plugin slash commands in place" \
  || fail "local uninstall leaves the plugin slash commands in place"

pre=$(jsonq .claude/settings.json '
import json,sys
s=json.load(open(sys.argv[1]))
print("\n".join(h.get("command","") for e in s.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[])))')
case "$pre" in
  *enforce-suite*) fail "local uninstall deregisters the hook" "still present" ;;
  *) pass "local uninstall deregisters the hook" ;;
esac

cd "$REPO" || exit 1
rm -rf "$PROJ"

# The reverse asymmetry: a global uninstall must not touch a local install.
suite "global uninstall does not reach into a project"
H5=$(new_home)
PROJ2=$(mktemp -d)
cd "$PROJ2" || exit 1
env HOME="$H5" bash "$REPO/install.sh" --no-bonsai >/dev/null 2>&1          # local
env HOME="$H5" bash "$REPO/install.sh" --global --no-bonsai >/dev/null 2>&1 # and global
env HOME="$H5" bash "$REPO/uninstall.sh" --global >/dev/null 2>&1
[ -f .claude/hooks/enforce-suite.sh ] \
  && pass "global uninstall leaves the project's local hook alone" \
  || fail "global uninstall leaves the project's local hook alone"
[ -f .claude/aether.manifest ] \
  && pass "global uninstall leaves the project's local manifest alone" \
  || fail "global uninstall leaves the project's local manifest alone"
[ -e "$H5/.local/share/aether/enforce-suite.sh" ] \
  && fail "global uninstall removed the global hook" \
  || pass "global uninstall removed the global hook"
cd "$REPO" || exit 1
rm -rf "$PROJ2"

summary
