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

for c in draft-commit.md draft-pr.md draft-changelog.md draft-summary.md critique-diff.md critique-plan.md; do
  [ -f "$H/.claude/commands/$c" ] && pass "command installed: $c" || fail "command installed: $c"
done
# None of the pre-1.0.0 names may appear on a fresh install.
for c in autocritic.md temper.md cairn-commit.md cairn-pr.md cairn-changelog.md cairn-summary.md; do
  [ -f "$H/.claude/commands/$c" ] && fail "old command absent: $c" || pass "old command absent: $c"
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
# ── every command a nudge names must actually exist ──────────────────────────
# This is the check that would have caught the whole class of drift before it
# existed: hooks and CLAUDE.md templates naming slash commands that no installer
# ships. It keeps catching it on every future rename.
suite "referenced commands exist"
SHIPPED=$(cd "$REPO" && ls plugins/*/.claude/commands/*.md | xargs -n1 basename | sed 's/\.md$//' | sort -u)
referenced=$(grep -rhoE '/[a-z][a-z0-9]+(-[a-z0-9]+)+' \
    "$REPO"/plugins/*/hooks/*.sh "$REPO"/hooks/*.sh \
    "$REPO"/templates/CLAUDE.md "$REPO"/plugins/*/templates/CLAUDE.md 2>/dev/null \
  | sed 's|^/||' | sort -u)
missing=""
for r in $referenced; do
  # Only consider tokens that look like one of our two command families;
  # everything else in these files is a path fragment or a flag.
  case "$r" in critique-*|draft-*) ;; *) continue ;; esac
  printf '%s\n' "$SHIPPED" | grep -qx "$r" || missing="$missing $r"
done
if [ -z "$missing" ]; then
  pass "every /critique-* and /draft-* named in hooks and templates is shipped"
else
  fail "every /critique-* and /draft-* named in hooks and templates is shipped" "missing:$missing"
fi

# And the reverse: no hook or template still names a pre-rename command.
stale=$(grep -rhoE '/(autocritic|cairn-(commit|pr|changelog|summary))\b' \
  "$REPO"/plugins/*/hooks/*.sh "$REPO"/hooks/*.sh \
  "$REPO"/templates/CLAUDE.md "$REPO"/plugins/*/templates/CLAUDE.md 2>/dev/null | sort -u)
if [ -z "$stale" ]; then
  pass "no hook or template names a pre-rename command"
else
  fail "no hook or template names a pre-rename command" "$stale"
fi

# ── per-plugin update must not resurrect old command names ───────────────────
# cairn/temper/whetstone used to re-download command files by name from the
# pre-monorepo repos. Those are archived but still serve content, so this would
# have written the old files straight back after the prune.
suite "plugin update cannot resurrect old commands"
# Comment lines are excluded: each CLI keeps a note explaining why the old
# network fetch was removed, and that note is worth keeping.
hits=$(grep -n 'raw.githubusercontent' "$REPO"/plugins/*/bin/* 2>/dev/null \
       | grep -vE ':[0-9]+: *#' || true)
if [ -z "$hits" ]; then
  pass "no plugin CLI fetches command files over the network"
else
  fail "no plugin CLI fetches command files over the network" "$hits"
fi

HR=$(new_home)
mkdir -p "$HR/.claude/commands"
env HOME="$HR" bash "$REPO/install.sh" --global --no-bonsai >/dev/null 2>&1
for c in autocritic.md temper.md cairn-commit.md; do
  printf 'resurrected\n' > "$HR/.claude/commands/$c"
done
for p in cairn temper whetstone; do
  env HOME="$HR" bash "$REPO/plugins/$p/bin/$p" update >/dev/null 2>&1 || true
done
resurrected=""
for c in autocritic.md temper.md cairn-commit.md cairn-pr.md cairn-changelog.md cairn-summary.md; do
  [ -f "$HR/.claude/commands/$c" ] && resurrected="$resurrected $c"
done
if [ -z "$resurrected" ]; then
  pass "running every plugin's update leaves no pre-rename command behind"
else
  fail "running every plugin's update leaves no pre-rename command behind" "found:$resurrected"
fi

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

# ── upgrading from the pre-rename command names ──────────────────────────────
# The case that decides whether the rename is safe to ship. An orphaned command
# file is not inert: it stays in the palette and still runs the stale copy.
suite "upgrade prunes superseded commands"
HU=$(new_home)
mkdir -p "$HU/.claude/commands"
OLD_NAMES="autocritic.md temper.md cairn-commit.md cairn-pr.md cairn-changelog.md cairn-summary.md"
for c in $OLD_NAMES; do printf 'stale copy of %s\n' "$c" > "$HU/.claude/commands/$c"; done
# A 0.1.0 manifest has no commands= line, so the installer must fall back to the
# known pre-rename set rather than finding nothing to prune.
printf 'version=0.1.0\nscope=global\n' > "$HU/.claude/aether.manifest"

env HOME="$HU" bash "$REPO/install.sh" --global --no-bonsai >"$HU/out.log" 2>&1
e=$?
assert_exit 0 "$e" "upgrade over a 0.1.0 install exits 0"
for c in $OLD_NAMES; do
  [ -f "$HU/.claude/commands/$c" ] && fail "pruned $c" || pass "pruned $c"
done
for c in critique-plan.md critique-diff.md draft-commit.md; do
  [ -f "$HU/.claude/commands/$c" ] && pass "installed $c" || fail "installed $c"
done
assert_contains "$(cat "$HU/.claude/aether.manifest")" "commands=" \
  "the manifest now records what it shipped"

# A hand-edited command must not vanish silently.
suite "prune preserves user edits"
HE=$(new_home)
mkdir -p "$HE/.claude/commands"
printf 'MY OWN HEAVILY EDITED VERSION\n' > "$HE/.claude/commands/cairn-commit.md"
cp "$REPO/plugins/cairn/.claude/commands/draft-pr.md" "$HE/.claude/commands/cairn-pr.md" 2>/dev/null || true
printf 'version=0.1.0\nscope=global\n' > "$HE/.claude/aether.manifest"
env HOME="$HE" bash "$REPO/install.sh" --global --no-bonsai >/dev/null 2>&1
[ -f "$HE/.claude/commands/cairn-commit.md.bak" ] \
  && pass "an edited command is backed up before removal" \
  || fail "an edited command is backed up before removal"
assert_contains "$(cat "$HE/.claude/commands/cairn-commit.md.bak" 2>/dev/null)" \
  "MY OWN HEAVILY EDITED" "the backup holds the user's content"

# ── a global install must not touch the current project ──────────────────────
# The prune loops over $COMMANDS_DIR only. Sweeping both scopes would mean
# installing globally from inside some unrelated repo deletes that repo's
# commands.
suite "prune is scope-limited"
HS=$(new_home)
PROJ_S=$(mktemp -d)
mkdir -p "$PROJ_S/.claude/commands"
printf 'a project-local command\n' > "$PROJ_S/.claude/commands/cairn-commit.md"
cd "$PROJ_S" || exit 1
env HOME="$HS" bash "$REPO/install.sh" --global --no-bonsai >/dev/null 2>&1
[ -f "$PROJ_S/.claude/commands/cairn-commit.md" ] \
  && pass "a --global install leaves the project's commands alone" \
  || fail "a --global install leaves the project's commands alone"
cd "$REPO" || exit 1
rm -rf "$PROJ_S"

# ── CLAUDE.md is refreshed, not skipped ──────────────────────────────────────
# Skipping froze the injected rules at whatever version wrote them first, so the
# block would keep naming commands the rename deleted.
suite "CLAUDE.md refresh"
HC=$(new_home)
mkdir -p "$HC/.claude"
printf 'my own notes\n\n<!-- aether:start -->\nRun /autocritic and /cairn-commit.\n<!-- aether:end -->\n' \
  > "$HC/.claude/CLAUDE.md"
env HOME="$HC" bash "$REPO/install.sh" --global --claude-md --no-bonsai >/dev/null 2>&1
C="$HC/.claude/CLAUDE.md"
assert_contains "$(cat "$C")" "/critique-plan" "the block is refreshed to the new names"
case "$(cat "$C")" in
  *"/autocritic"*) fail "the stale block is gone" "still names /autocritic" ;;
  *) pass "the stale block is gone" ;;
esac
n=$(grep -c '<!-- aether:start -->' "$C")
assert_eq "1" "$n" "refresh leaves exactly one aether block"
assert_contains "$(cat "$C")" "my own notes" "content outside the sentinels is preserved"
[ -f "$C.bak" ] && pass "CLAUDE.md is backed up before refresh" || fail "CLAUDE.md is backed up before refresh"

# ── JSON backend equivalence ─────────────────────────────────────────────────
# install.sh rewrites settings.json with python3, node or jq, whichever is
# present. python3 always wins in practice, so the other two branches would
# never run on a developer machine — AETHER_JSON_BACKEND pins each one so all
# three are exercised and compared. Seeded with hooks and permissions that must
# be migrated, so the comparison covers removal as well as insertion.
suite "JSON backend equivalence"
SEED='{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "/old/enforce-cairn.sh"}]},
      {"matcher": "Other", "hooks": [{"type": "command", "command": "/keep/me.sh"}]}
    ],
    "PostToolUse": [
      {"matcher": "Bash|Write|Edit", "hooks": [{"type": "command", "command": "/old/post-cairn.sh"}]}
    ]
  },
  "permissions": {"allow": ["Bash", "mcp__bonsai_py__*", "SomethingElse"]}
}'

RESULTS=()
for backend in python3 node jq; do
  if ! command -v "$backend" >/dev/null 2>&1; then
    pass "$backend not installed — branch skipped"
    continue
  fi
  HB=$(new_home)
  mkdir -p "$HB/.claude"
  printf '%s\n' "$SEED" > "$HB/.claude/settings.json"
  env HOME="$HB" AETHER_JSON_BACKEND="$backend" \
    bash "$REPO/install.sh" --global --no-bonsai >"$HB/out.log" 2>&1
  e=$?
  assert_exit 0 "$e" "install succeeds with the $backend backend"
  # Normalise: hook paths embed the throwaway HOME.
  norm=$(python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))
print(json.dumps(s, indent=2, sort_keys=True).replace(sys.argv[2], "<HOME>"))
' "$HB/.claude/settings.json" "$HB" 2>/dev/null)
  RESULTS+=("$backend:$norm")
done

if [ "${#RESULTS[@]}" -ge 2 ]; then
  first_name="${RESULTS[0]%%:*}"; first_val="${RESULTS[0]#*:}"
  for r in "${RESULTS[@]:1}"; do
    name="${r%%:*}"; val="${r#*:}"
    if [ "$first_val" = "$val" ]; then
      pass "$name backend produces the same settings.json as $first_name"
    else
      fail "$name backend produces the same settings.json as $first_name" \
        "$(diff <(printf '%s' "$first_val") <(printf '%s' "$val") | head -12)"
    fi
  done
  # And the shared result must actually be correct, not merely consistent.
  assert_contains "$first_val" "enforce-suite.sh"  "all backends register the suite hook"
  assert_contains "$first_val" "post-cairn.sh"     "all backends preserve the PostToolUse hook"
  assert_contains "$first_val" "mcp__bonsai-py__*" "all backends write the hyphen permission"
  assert_contains "$first_val" "/keep/me.sh"       "all backends leave unrelated hooks alone"
  case "$first_val" in
    *enforce-cairn*) fail "all backends strip the superseded PreToolUse hook" ;;
    *) pass "all backends strip the superseded PreToolUse hook" ;;
  esac
  case "$first_val" in
    *mcp__bonsai_py__*) fail "all backends drop the underscore permission" ;;
    *) pass "all backends drop the underscore permission" ;;
  esac
fi

summary
