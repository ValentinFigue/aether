#!/usr/bin/env bash
# tests/test_install.sh — the root installer.
#
# Every case runs against a throwaway HOME passed via `env` for that one
# command. Never `export HOME` here: it would silently redirect the rest of the
# suite, and anything else reading ~/.claude, at the real home directory.
#
# bonsai is excluded from most cases (--no-bonsai) because its uv/npm build
# takes minutes; its skip path is covered separately at the end.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

FAKE_HOMES=()
new_home() {
  local h; h=$(mktemp -d)
  FAKE_HOMES+=("$h")
  printf '%s' "$h"
}
cleanup() { for h in "${FAKE_HOMES[@]}"; do rm -rf "$h"; done; }
trap cleanup EXIT

# jq-free JSON probe
jsonq() { python3 -c "$2" "$1" 2>/dev/null; }

# ── a clean global install ───────────────────────────────────────────────────
suite "global install"
H=$(new_home)
if env HOME="$H" bash "$REPO/install.sh" --global --claude-md --no-bonsai >"$H/out.log" 2>&1; then
  pass "install exits 0"
else
  fail "install exits 0" "$(tail -5 "$H/out.log")"
fi

for c in cairn-commit.md cairn-pr.md cairn-changelog.md cairn-summary.md temper.md autocritic.md; do
  [ -f "$H/.claude/commands/$c" ] && pass "command installed: $c" || fail "command installed: $c"
done

[ -x "$H/.local/share/aether/enforce-suite.sh" ] \
  && pass "enforce-suite.sh installed and executable" \
  || fail "enforce-suite.sh installed and executable"

for g in cairn whetstone temper; do
  [ -f "$H/.local/share/aether/gates/enforce-$g.sh" ] \
    && pass "gate installed: enforce-$g.sh" || fail "gate installed: enforce-$g.sh"
done
# bonsai was skipped, so its gate must not be there — the suite should never
# advise MCP tools the user has not installed.
[ -f "$H/.local/share/aether/gates/enforce-bonsai.sh" ] \
  && fail "no bonsai gate when bonsai is skipped" \
  || pass "no bonsai gate when bonsai is skipped"

[ -x "$H/.local/bin/aether" ] && pass "aether CLI installed" || fail "aether CLI installed"

# ── hook wiring ──────────────────────────────────────────────────────────────
suite "hook wiring"
S="$H/.claude/settings.json"
pre=$(jsonq "$S" '
import json,sys
s=json.load(open(sys.argv[1]))
print("\n".join(h.get("command","") for e in s.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[])))')
n=$(printf '%s' "$pre" | grep -c 'enforce-suite.sh' || true)
assert_eq "1" "$n" "exactly one enforce-suite.sh PreToolUse hook"
for dead in enforce-cairn enforce-temper enforce-whetstone enforce-bonsai; do
  case "$pre" in
    *"$dead"*) fail "no leftover $dead PreToolUse hook" ;;
    *) pass "no leftover $dead PreToolUse hook" ;;
  esac
done

post=$(jsonq "$S" '
import json,sys
s=json.load(open(sys.argv[1]))
print("\n".join(h.get("command","") for e in s.get("hooks",{}).get("PostToolUse",[]) for h in e.get("hooks",[])))')
assert_contains "$post" "post-cairn.sh" "post-cairn.sh PostToolUse hook survives the install"

# ── permissions ──────────────────────────────────────────────────────────────
suite "permissions"
allow=$(jsonq "$S" '
import json,sys
print(" ".join(json.load(open(sys.argv[1])).get("permissions",{}).get("allow",[])))')
assert_contains "$allow" "mcp__bonsai-py__*" "MCP permission uses the hyphen spelling"
assert_contains "$allow" "mcp__bonsai-ts__*" "MCP permission uses the hyphen spelling (ts)"
case "$allow" in
  *mcp__bonsai_py__*) fail "underscore MCP permission is not written" "found in: $allow" ;;
  *) pass "underscore MCP permission is not written" ;;
esac

# ── CLAUDE.md ────────────────────────────────────────────────────────────────
suite "CLAUDE.md"
C="$H/.claude/CLAUDE.md"
n=$(grep -c '<!-- aether:start -->' "$C" 2>/dev/null || true)
assert_eq "1" "$n" "exactly one aether block"
for m in cairn temper whetstone bonsai; do
  n=$(grep -c "<!-- ${m}:start -->" "$C" 2>/dev/null || true)
  assert_eq "0" "$n" "no standalone $m block (superseded by the aether block)"
done

# ── manifest ─────────────────────────────────────────────────────────────────
suite "manifest"
M="$H/.claude/aether.manifest"
assert_contains "$(cat "$M")" "version=1.0.0" "manifest records the version"
assert_contains "$(cat "$M")" "repo=$REPO"    "manifest records the clone path"
assert_contains "$(cat "$M")" "gates="        "manifest records the gates directory"

# ── backups ──────────────────────────────────────────────────────────────────
suite "backups"
[ -f "$S.bak" ] && pass "settings.json.bak written before mutation" \
                || fail "settings.json.bak written before mutation"

# ── idempotence ──────────────────────────────────────────────────────────────
suite "idempotence"
env HOME="$H" bash "$REPO/install.sh" --global --claude-md --no-bonsai >"$H/out2.log" 2>&1
e=$?
assert_exit 0 "$e" "second install exits 0"
pre=$(jsonq "$S" '
import json,sys
s=json.load(open(sys.argv[1]))
print("\n".join(h.get("command","") for e in s.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[])))')
n=$(printf '%s' "$pre" | grep -c 'enforce-suite.sh' || true)
assert_eq "1" "$n" "still exactly one enforce-suite.sh hook after re-install"
n=$(grep -c '<!-- aether:start -->' "$C" 2>/dev/null || true)
assert_eq "1" "$n" "still exactly one aether CLAUDE.md block after re-install"
allow=$(jsonq "$S" '
import json,sys
print(" ".join(json.load(open(sys.argv[1])).get("permissions",{}).get("allow",[])))')
n=$(printf '%s' "$allow" | tr ' ' '\n' | grep -c 'mcp__bonsai-py__\*' || true)
assert_eq "1" "$n" "permissions are not duplicated on re-install"

# ── migration from a pre-suite install ───────────────────────────────────────
# A machine upgrading from standalone plugins carries per-plugin PreToolUse
# hooks (superseded) and PostToolUse hooks (still needed).
suite "migration from standalone plugins"
H2=$(new_home)
mkdir -p "$H2/.claude"
cat > "$H2/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "/old/enforce-cairn.sh"}]},
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "/old/enforce-temper.sh"}]}
    ],
    "PostToolUse": [
      {"matcher": "Bash|Write|Edit", "hooks": [{"type": "command", "command": "/old/post-cairn.sh"}]},
      {"matcher": "Write|Edit|MultiEdit", "hooks": [{"type": "command", "command": "/old/post-bonsai.sh"}]}
    ]
  },
  "permissions": {"allow": ["Bash", "mcp__bonsai_py__*"]}
}
JSON
env HOME="$H2" bash "$REPO/install.sh" --global --no-bonsai >"$H2/out.log" 2>&1
S2="$H2/.claude/settings.json"
pre=$(jsonq "$S2" '
import json,sys
s=json.load(open(sys.argv[1]))
print("\n".join(h.get("command","") for e in s.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[])))')
case "$pre" in
  *enforce-cairn*|*enforce-temper*) fail "old per-plugin PreToolUse hooks removed" "still present: $pre" ;;
  *) pass "old per-plugin PreToolUse hooks removed" ;;
esac
post=$(jsonq "$S2" '
import json,sys
s=json.load(open(sys.argv[1]))
print("\n".join(h.get("command","") for e in s.get("hooks",{}).get("PostToolUse",[]) for h in e.get("hooks",[])))')
assert_contains "$post" "post-cairn.sh"  "existing post-cairn hook is preserved"
assert_contains "$post" "post-bonsai.sh" "existing post-bonsai hook is preserved"
allow=$(jsonq "$S2" '
import json,sys
print(" ".join(json.load(open(sys.argv[1])).get("permissions",{}).get("allow",[])))')
case "$allow" in
  *mcp__bonsai_py__*) fail "stale underscore permission is cleaned up" "still present: $allow" ;;
  *) pass "stale underscore permission is cleaned up" ;;
esac

# ── failure is reported, not swallowed ───────────────────────────────────────
# Installs used to print a green tick unconditionally, so a total failure still
# looked like success.
suite "failure reporting"
H3=$(new_home)
mv "$REPO/plugins/cairn/bin/cairn" "$REPO/plugins/cairn/bin/cairn.bak"
env HOME="$H3" bash "$REPO/install.sh" --global --no-bonsai >"$H3/out.log" 2>&1
e=$?
mv "$REPO/plugins/cairn/bin/cairn.bak" "$REPO/plugins/cairn/bin/cairn"
assert_exit 1 "$e" "install exits non-zero when a plugin fails"
assert_contains "$(cat "$H3/out.log")" "✗ cairn" "the failing plugin is named"

# ── bonsai prerequisite handling ─────────────────────────────────────────────
suite "bonsai prerequisites"
H4=$(new_home)
# A PATH without uv/node/npm must skip bonsai with instructions, not fail.
env HOME="$H4" PATH="/usr/bin:/bin" bash "$REPO/install.sh" --global >"$H4/out.log" 2>&1
e=$?
assert_exit 0 "$e" "missing uv/node/npm skips bonsai without failing the suite"
assert_contains "$(cat "$H4/out.log")" "bonsai: skipped" "the skip is reported"
assert_contains "$(cat "$H4/out.log")" "plugins/bonsai/install.sh" "the skip explains how to finish later"

# ── no network ───────────────────────────────────────────────────────────────
suite "offline"
hits=$(grep -rn 'raw.githubusercontent' "$REPO/install.sh" "$REPO/bin/aether" \
         "$REPO"/plugins/*/install.sh 2>/dev/null | grep -v '^\s*#' | wc -l | tr -d ' ')
assert_eq "0" "$hits" "no raw.githubusercontent fetches in any installer"

# ── MCP tool-name spelling ───────────────────────────────────────────────────
# The servers register as bonsai-py / bonsai-ts, so tools are mcp__bonsai-py__*.
# The underscore spelling reads as correct but matches nothing, and it had been
# copied into six files. Everything that writes or matches it must use hyphens;
# the only permitted underscore references are the cleanup lists that strip the
# old spelling from existing configs.
suite "MCP tool-name spelling"
offenders=$(grep -rln 'mcp__bonsai_py__\|mcp__bonsai_ts__' "$REPO" 2>/dev/null \
  | grep -v '/\.git/' \
  | grep -vE '/(__pycache__|node_modules|\.venv|dist)/' \
  | grep -vE '/(tests|\.claude/plans)/' \
  | grep -vE '/(install|uninstall)\.sh$' \
  | grep -vE '/bin/(bonsai|aether)$' \
  | grep -vE '/__main__\.py$' \
  | grep -vE '/CHANGELOG\.md$' || true)
if [ -z "$offenders" ]; then
  pass "no underscore MCP spellings outside cleanup paths"
else
  fail "no underscore MCP spellings outside cleanup paths" $offenders
fi

# Files that legitimately mention the old spelling must only remove it, never add it.
for f in "$REPO/install.sh" "$REPO/plugins/bonsai/install.sh"; do
  adds=$(grep -n 'allow.append("mcp__bonsai_\|"mcp__bonsai_py__\*", "mcp__bonsai_ts__\*"\]' "$f" 2>/dev/null \
         | grep -v 'dead\|remove\|filter\|select' | wc -l | tr -d ' ')
  assert_eq "0" "$adds" "$(basename "$(dirname "$f")")/$(basename "$f") never writes the underscore spelling"
done

summary
