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

[ -x "$H/.aether/hooks/enforce-suite.sh" ] \
  && pass "enforce-suite.sh installed and executable" \
  || fail "enforce-suite.sh installed and executable"

for g in cairn whetstone temper; do
  [ -f "$H/.aether/hooks/gates/enforce-$g.sh" ] \
    && pass "gate installed: enforce-$g.sh" || fail "gate installed: enforce-$g.sh"
done
# bonsai was skipped, so its gate must not be there — the suite should never
# advise MCP tools the user has not installed.
[ -f "$H/.aether/hooks/gates/enforce-bonsai.sh" ] \
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
# Permissions come from the manifests of the plugins that actually installed.
# This run used --no-bonsai, so bonsai's MCP permissions must be absent — the
# old installer granted them unconditionally, for a plugin that was not there.
case "$allow" in
  *mcp__bonsai-py__*) fail "no MCP permission when bonsai is skipped" "granted anyway: $allow" ;;
  *) pass "no MCP permission when bonsai is skipped" ;;
esac
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
M="$H/.aether/manifest"
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
n=$(printf '%s' "$allow" | tr ' ' '\n' | grep -c '^Bash$' || true)
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
assert_contains "$(cat "$H4/out.log")" "aether install bonsai" "the skip explains how to finish later"

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
# ── prune failure must not abort the install ─────────────────────────────────
# The prune runs under `set -e` after the plugins are installed but before the
# hook, gates, permissions and manifest are written. An unremovable file used to
# abort there, leaving a half-configured machine and no error explaining it.
# The old command is made unreadable rather than the directory unwritable, so
# only the prune fails and the rest of the install proceeds normally.
suite "prune failure is not fatal"
HG=$(new_home)
mkdir -p "$HG/.claude/commands"
printf 'old\n' > "$HG/.claude/commands/cairn-commit.md"
chmod 000 "$HG/.claude/commands/cairn-commit.md"
mkdir -p "$HG/.aether"
printf 'version=0.1.0\nscope=global\n' > "$HG/.aether/manifest"
env HOME="$HG" bash "$REPO/install.sh" --global --no-bonsai >"$HG/out.log" 2>&1
e=$?
chmod 644 "$HG/.claude/commands/cairn-commit.md" 2>/dev/null || true
assert_exit 0 "$e" "an unremovable superseded command does not fail the install"
assert_contains "$(cat "$HG/out.log")" "Could not remove superseded" "the failure is reported, not swallowed"
grep -q '^commands=' "$HG/.aether/manifest" \
  && pass "the manifest is still written after a prune failure" \
  || fail "the manifest is still written after a prune failure"
[ -x "$HG/.aether/hooks/enforce-suite.sh" ] \
  && pass "the hook is still installed after a prune failure" \
  || fail "the hook is still installed after a prune failure"

# ── command files carry a real palette description ───────────────────────────
# Four of the six used to start with "Parse $ARGUMENTS for flags:", which is what
# the palette showed. Guard against that regressing.
suite "palette descriptions"
# The owning plugin is derived from the path rather than listed, so a fifth
# plugin is covered by existing — the same reason the engine stopped hardcoding
# PLUGINS=.
for f in "$REPO"/plugins/*/.claude/commands/*.md; do
  n=$(basename "$f")
  owner=$(basename "$(dirname "$(dirname "$(dirname "$f")")")")
  first=$(head -1 "$f")
  case "$first" in
    "Parse \$ARGUMENTS"*|"#"*|"")
      fail "$n starts with a real description" "line 1 is: ${first:0:50}" ;;
    *"($owner)"*)
      pass "$n starts with a real description naming its plugin" ;;
    *)
      fail "$n names its owning plugin on line 1" "line 1 is: ${first:0:60}" ;;
  esac
done

# ── critique-pr reuses temper's critics rather than restating them ───────────
# Duplicating the four critic definitions here is the same trap the suite hook
# was rescued from; a copy would drift from critique-diff.md.
suite "critique-pr does not duplicate the critics"
CPR="$REPO/plugins/temper/.claude/commands/critique-pr.md"
[ -f "$CPR" ] && pass "critique-pr.md exists" || fail "critique-pr.md exists"
assert_contains "$(cat "$CPR")" "critique-diff.md" "it points at critique-diff.md for the definitions"
for c in Correctness Design Risk Coverage; do
  assert_contains "$(cat "$CPR")" "$c" "it names the $c critic"
done
assert_contains "$(cat "$CPR")" "Description accuracy" "it adds the description critic"
# The full temper critic prose must not be copied in. "You are a senior engineer"
# opens each definition in critique-diff.md; it must appear zero times here.
n=$(grep -c 'You are a senior engineer' "$CPR" || true)
assert_eq "0" "$n" "the full critic definitions are not copied into critique-pr.md"

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

# ── bonsai's MCP servers ─────────────────────────────────────────────────────
# This was written once with the spec on a pipe and the python program on a
# heredoc. `python3 -` reads its program from stdin, so the heredoc claimed
# stdin, sys.stdin.read() returned nothing, and the engine wrote an empty
# mcpServers map and reported success. Registration is asserted directly because
# a full bonsai install needs uv and npm and a minute of build time.
suite "MCP registration"
HM=$(new_home)
# AETHER_REPO is what makes this testable without a real install: sourcing the
# engine out of an eval leaves BASH_SOURCE pointing at the eval, so _repo_root
# cannot find the clone on its own.
mcp_sync() {
  HOME="$HM" AETHER_REPO="$REPO" bash -c '
    . "'"$REPO"'/hooks/aether-config.sh" 2>/dev/null
    eval "$(sed "/^COMMAND=/,\$d" "'"$REPO"'/bin/aether")"
    _json_mcp_sync bonsai "'"$REPO"'/plugins/bonsai" "$1"' _ "$1" 2>&1
}
mcp_sync add
got=$(python3 - "$HM/.claude.json" <<'PYEOF'
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: print("no file"); raise SystemExit
s = d.get("mcpServers", {})
print(" ".join(sorted(s)) or "EMPTY")
PYEOF
)
assert_eq "bonsai-py bonsai-ts" "$got" "both MCP servers are registered"

for srv in bonsai-py bonsai-ts; do
  a=$(python3 - "$HM/.claude.json" "$srv" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))["mcpServers"][sys.argv[2]]
print(" ".join(d["args"]))
PYEOF
)
  case "$a" in
    /*|*" /"*) pass "$srv args point at an absolute in-clone path" ;;
    *) fail "$srv args point at an absolute in-clone path" "args: $a" ;;
  esac
  case "$a" in
    *'${PLUGIN_ROOT}'*) fail "$srv has PLUGIN_ROOT interpolated" "left literal: $a" ;;
    *) pass "$srv has PLUGIN_ROOT interpolated" ;;
  esac
done

# And the guard against writing one that cannot launch: with no clone to resolve
# against, an entry with an empty command is worse than no entry, because Claude
# Code would try to run it.
HM2=$(new_home)
out=$(HOME="$HM2" bash -c '
  . "'"$REPO"'/hooks/aether-config.sh" 2>/dev/null
  eval "$(sed "/^COMMAND=/,\$d" "'"$REPO"'/bin/aether")"
  _json_mcp_sync bonsai "'"$REPO"'/plugins/bonsai" add || true' 2>&1)
assert_contains "$out" "not registered" "an unresolvable server is refused, not half-written"
if [ -f "$HM2/.claude.json" ]; then
  bad=$(python3 - "$HM2/.claude.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])).get("mcpServers", {})
print(" ".join(n for n, c in d.items() if not c.get("command")))
PYEOF
)
  [ -z "$bad" ] && pass "no server with an empty command was written" \
                || fail "no server with an empty command was written" "$bad"
else
  pass "no server with an empty command was written"
fi

mcp_sync remove
got=$(python3 - "$HM/.claude.json" <<'PYEOF'
import json, sys
print(" ".join(sorted(json.load(open(sys.argv[1])).get("mcpServers", {}))) or "EMPTY")
PYEOF
)
assert_eq "EMPTY" "$got" "uninstall deregisters both"

# The servers themselves, when the build output is already there. Skipped rather
# than built, so the suite does not depend on uv and npm.
if [ -f "$REPO/plugins/bonsai/ts/dist/server.js" ] && command -v node >/dev/null 2>&1; then
  n=$(printf '%s
' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | node "$REPO/plugins/bonsai/ts/dist/server.js" 2>/dev/null \
    | python3 -c "
import sys, json
for l in sys.stdin:
    try: m = json.loads(l)
    except Exception: continue
    if m.get('id') == 2: print(len(m['result']['tools'])); break
")
  [ "${n:-0}" -ge 5 ] \
    && pass "bonsai-ts answers a handshake ($n tools)" \
    || fail "bonsai-ts answers a handshake" "got: ${n:-no response}"
fi

# ── the hook stays cheap ─────────────────────────────────────────────────────
# It runs on every Bash, Write and Edit. Resolving each key separately meant one
# awk per key — twelve per tool call once the installer started seeding a config,
# which took the hook from 81ms to 105ms. Counting processes rather than timing
# keeps this stable on a loaded CI machine.
suite "the PreToolUse hook does not spawn a process per key"
HK=$(new_home)
env HOME="$HK" bash "$REPO/install.sh" --global --no-bonsai >/dev/null 2>&1
n=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    | env HOME="$HK" bash -x "$HK/.aether/hooks/enforce-suite.sh" 2>&1 >/dev/null \
    | grep -c '+ awk' || true)
[ "$n" -le 3 ] \
  && pass "at most 3 awk processes per invocation (saw $n)" \
  || fail "at most 3 awk processes per invocation" "saw $n — the per-key path is back"

# ── the CLAUDE.md splice is idempotent ───────────────────────────────────────
# Removing the block took the block but not the blank line that separated it,
# and the re-append added a fresh one — so every install grew CLAUDE.md by
# exactly one line, forever. 295, 296, 297…
suite "CLAUDE.md splice is idempotent"
HB=$(new_home)
mkdir -p "$HB/.claude"
printf '# My own rules\n\nDo the thing.\n' > "$HB/.claude/CLAUDE.md"
for _ in 1 2 3; do
  env HOME="$HB" bash "$REPO/install.sh" --global --claude-md --no-bonsai >/dev/null 2>&1
done
first=$(env HOME="$HB" bash -c 'wc -l < "$HOME/.claude/CLAUDE.md"' | tr -d ' ')
env HOME="$HB" bash "$REPO/install.sh" --global --claude-md --no-bonsai >/dev/null 2>&1
again=$(env HOME="$HB" bash -c 'wc -l < "$HOME/.claude/CLAUDE.md"' | tr -d ' ')
assert_eq "$first" "$again" "a fourth install does not grow CLAUDE.md"
n=$(grep -c 'aether:start' "$HB/.claude/CLAUDE.md" || true)
assert_eq "1" "$n" "the block still appears exactly once"
assert_contains "$(cat "$HB/.claude/CLAUDE.md")" "Do the thing." "the user's own content survives"
head -1 "$HB/.claude/CLAUDE.md" | grep -q '^# My own rules$' \
  && pass "…and stays at the top of the file" \
  || fail "…and stays at the top of the file" "$(head -1 "$HB/.claude/CLAUDE.md")"

# ── a script may overwrite itself ────────────────────────────────────────────
# `aether update` runs from ~/.local/bin/aether and copies a new bin/aether over
# it. `cp` truncates and rewrites in place, and bash reads a script incrementally
# as it executes — so the byte offsets shifted under the interpreter and it
# resumed mid-token: `syntax error near unexpected token ';;'`, from the
# dispatcher's case, after the install had otherwise reported success.
suite "install replaces files by rename"
HX=$(new_home)
mkdir -p "$HX/bin"
printf 'echo old\n' > "$HX/bin/target"
before=$(ls -i "$HX/bin/target" | awk '{print $1}')
AETHER_REPO="$REPO" bash -c '
  . "'"$REPO"'/hooks/aether-config.sh" 2>/dev/null
  eval "$(sed "/^COMMAND=/,\$d" "'"$REPO"'/bin/aether")"
  _op_copy "'"$REPO"'/bin/aether" "'"$HX"'/bin/target"' >/dev/null 2>&1
after=$(ls -i "$HX/bin/target" | awk '{print $1}')
[ "$before" != "$after" ] \
  && pass "_op_copy replaces the directory entry, not the file contents" \
  || fail "_op_copy replaces the directory entry, not the file contents" \
         "inode unchanged ($before) — a running script would be corrupted"
[ -z "$(ls "$HX/bin/" | grep aether-tmp)" ] \
  && pass "no temp file is left behind" \
  || fail "no temp file is left behind" "$(ls "$HX/bin/")"

# The real thing: a script that overwrites itself mid-run must still finish.
SELF=$(mktemp -d)
cat > "$SELF/grow.sh" <<'GROWEOF'
#!/usr/bin/env bash
. "$AE_LIB" 2>/dev/null
eval "$(sed '/^COMMAND=/,$d' "$AE_CLI")"
_op_copy "$AE_BIG" "$0"
case ok in ok) printf 'survived
' ;; esac
GROWEOF
chmod +x "$SELF/grow.sh"
out=$(AE_LIB="$REPO/hooks/aether-config.sh" AE_CLI="$REPO/bin/aether" \
      AE_BIG="$REPO/bin/aether" AETHER_REPO="$REPO" bash "$SELF/grow.sh" 2>&1)
# Assert the output is *exactly* the expected line. Matching only on "syntax
# error" was too weak: mid-token resumption can also surface as
# `lear: command not found`, which is the same corruption wearing another hat.
assert_eq "survived" "$out" "a script that overwrites itself runs to completion, silently"
rm -rf "$SELF"

# ── a relocated hook is registered once ──────────────────────────────────────
# cairn used to install standalone into ~/.local/share/cairn/. A machine that had
# done that ended up with post-cairn.sh registered twice — the old path and the
# new one — so it fired twice on every Bash, Write and Edit. Keying the dedupe on
# the script's basename covers every past and future location without a list.
suite "hook registration is idempotent across a move"
HR=$(new_home)
mkdir -p "$HR/.claude" "$HR/.local/share/cairn"
printf 'exit 0\n' > "$HR/.local/share/cairn/post-cairn.sh"
python3 - "$HR" <<'PYEOF'
import json, sys
h = sys.argv[1]
json.dump({"hooks": {"PostToolUse": [{"matcher": "Bash|Write|Edit", "hooks": [
    {"type": "command", "command": h + "/.local/share/cairn/post-cairn.sh"}]}]}},
    open(h + "/.claude/settings.json", "w"), indent=2)
PYEOF
env HOME="$HR" bash "$REPO/install.sh" --global --no-bonsai >/dev/null 2>&1
n=$(python3 - "$HR/.claude/settings.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
print(sum(1 for e in d.get("hooks", {}).get("PostToolUse", [])
            for h in e.get("hooks", [])
            if h.get("command", "").endswith("post-cairn.sh")))
PYEOF
)
assert_eq "1" "$n" "post-cairn.sh is registered exactly once after a relocation"

# Installing twice must not add a second copy either.
env HOME="$HR" bash "$REPO/install.sh" --global --no-bonsai >/dev/null 2>&1
n=$(python3 - "$HR/.claude/settings.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
print(sum(1 for e in d.get("hooks", {}).get("PostToolUse", [])
            for h in e.get("hooks", [])
            if h.get("command", "").endswith("post-cairn.sh")))
PYEOF
)
assert_eq "1" "$n" "…and still once after a second install"

# ── a plugin is a manifest plus assets ───────────────────────────────────────
# trellis exists to prove this: it ships no install.sh and no uninstall.sh, so if
# the engine needs one, trellis cannot be installed at all.
suite "adding a plugin needs no installer"
[ -f "$REPO/plugins/trellis/install.sh" ] \
  && fail "trellis ships no installer" "install.sh exists — the proof is void" \
  || pass "trellis ships no installer"
[ -f "$REPO/plugins/trellis/uninstall.sh" ] \
  && fail "trellis ships no uninstaller" "uninstall.sh exists" \
  || pass "trellis ships no uninstaller"

HP=$(new_home)
env HOME="$HP" bash "$REPO/bin/aether" install trellis global >/dev/null 2>&1
[ -f "$HP/.claude/commands/draft-config.md" ] \
  && pass "aether install trellis installs its command" \
  || fail "aether install trellis installs its command"
assert_contains "$(env HOME="$HP" bash "$REPO/bin/aether" status 2>&1)" "trellis" \
  "a new plugin appears in status because it exists"
assert_contains "$(env HOME="$HP" bash "$REPO/bin/aether" config show trellis 2>&1)" "enabled" \
  "…and its schema is read from the same manifest"

env HOME="$HP" bash "$REPO/bin/aether" uninstall trellis global >/dev/null 2>&1
[ -f "$HP/.claude/commands/draft-config.md" ] \
  && fail "aether uninstall trellis removes its command" \
  || pass "aether uninstall trellis removes its command"

# Its command must not tell a critic to run something that never terminates.
DC="$REPO/plugins/trellis/.claude/commands/draft-config.md"
for forbidden in watch serve deploy; do
  grep -qi "never select" "$DC" && grep -qi "$forbidden" "$DC" \
    && pass "draft-config forbids '$forbidden' commands" \
    || fail "draft-config forbids '$forbidden' commands"
done

# ── --dry-run ────────────────────────────────────────────────────────────────
# A documented flag that has now regressed twice: once when the installers
# became wrappers, and once when the config seeding and migration were added.
# "Creates nothing" includes empty directories, since a stray .aether/ changes
# where output lands.
suite "--dry-run writes nothing"
HD=$(new_home)
mkdir -p "$HD/.claude"
printf 'auto_nudge_lines: 999\n' > "$HD/.claude/temper.config"   # something to migrate
snapshot() { ( cd "$HD" && find . | sort ); }
before=$(snapshot)
out=$(env HOME="$HD" bash "$REPO/install.sh" --global --claude-md --dry-run 2>&1); e=$?
assert_exit 0 "$e" "--dry-run exits 0"
assert_contains "$out" "dry-run" "--dry-run says so"
assert_eq "$before" "$(snapshot)" "--dry-run creates no files and no directories"
# …and does not claim it did. "✓ hook registered" in a dry run is untrue, and the
# earlier dry-run bugs were the same failure one level down: doing the work.
case "$out" in
  *"✓"*) fail "--dry-run never prints a ✓" "output contains a completed-step mark" ;;
  *) pass "--dry-run never prints a ✓" ;;
esac
assert_contains "$out" "not applied" "--dry-run marks each step as not applied"
[ -f "$HD/.claude/temper.config" ] \
  && pass "--dry-run does not migrate the old config" \
  || fail "--dry-run does not migrate the old config"

# ── upgrading from the pre-1.0 layout ────────────────────────────────────────
# The old layout put the global hook in ~/.local/share/aether/. Moving it means
# settings.json has to stop pointing at the old path — in BOTH phases. The
# stale-hook cleanup only ever handled PreToolUse, so an upgrade left a
# PostToolUse entry aimed at a directory that no longer exists, which Claude Code
# would then try to run on every Bash, Write and Edit call.
suite "upgrade deregisters the retired hook directory"
for backend in python3 node jq; do
  command -v "$backend" >/dev/null 2>&1 || continue
  HL=$(new_home)
  mkdir -p "$HL/.claude" "$HL/.local/share/aether/gates" "$HL/.local/share/aether/plugin-hooks"
  printf 'exit 0\n' > "$HL/.local/share/aether/enforce-suite.sh"
  printf 'exit 0\n' > "$HL/.local/share/aether/plugin-hooks/post-cairn.sh"
  python3 - "$HL" <<'PYEOF'
import json, sys
h = sys.argv[1]
old = h + "/.local/share/aether"
json.dump({"hooks": {
    "PreToolUse":  [{"matcher": "Bash|Write|Edit|MultiEdit",
                     "hooks": [{"type": "command", "command": old + "/enforce-suite.sh"}]}],
    "PostToolUse": [{"matcher": "Bash|Write|Edit",
                     "hooks": [{"type": "command", "command": old + "/plugin-hooks/post-cairn.sh"}]}],
}}, open(h + "/.claude/settings.json", "w"), indent=2)
PYEOF
  env HOME="$HL" AETHER_JSON_BACKEND="$backend" bash "$REPO/install.sh" --global --no-bonsai >/dev/null 2>&1
  dangling=$(python3 - "$HL" <<'PYEOF'
import json, os, sys
h = sys.argv[1]
d = json.load(open(h + "/.claude/settings.json"))
bad = [p + ":" + hk["command"]
       for p in ("PreToolUse", "PostToolUse")
       for e in d.get("hooks", {}).get(p, [])
       for hk in e.get("hooks", [])
       if not os.path.exists(hk["command"])]
print(" ".join(bad))
PYEOF
)
  [ -z "$dangling" ]     && pass "$backend: upgrade leaves no hook pointing at a missing script"     || fail "$backend: upgrade leaves no hook pointing at a missing script" "$dangling"
  [ -e "$HL/.local/share/aether" ]     && fail "$backend: the retired directory is gone"     || pass "$backend: the retired directory is gone"
  [ -f "$HL/.local/share/aether.bak/enforce-suite.sh" ]     && pass "$backend: …and backed up first"     || fail "$backend: …and backed up first"
done

suite "MCP tool-name spelling"
offenders=$(grep -rln 'mcp__bonsai_py__\|mcp__bonsai_ts__' "$REPO" 2>/dev/null \
  | grep -v '/\.git/' \
  | grep -vE '/(__pycache__|node_modules|\.venv|dist)/' \
  | grep -vE '/(tests|\.claude/plans|\.aether/out)/' \
  | grep -vE '/(install|uninstall)\.sh$' \
  | grep -vE '/bin/(bonsai|aether)$' \
  | grep -vE '/__main__\.py$' \
  | grep -vE '/CHANGELOG\.md$' \
  | grep -vE '/aether\.plugin$' || true)
if [ -z "$offenders" ]; then
  pass "no underscore MCP spellings outside cleanup paths"
else
  fail "no underscore MCP spellings outside cleanup paths" $offenders
fi

# A manifest may name the old spelling only under legacy_permissions, which is the
# declaration that it should be *removed*. Anywhere else in a manifest is a bug.
for m in "$REPO"/plugins/*/aether.plugin; do
  bad=$(grep -n 'mcp__bonsai_py__\|mcp__bonsai_ts__' "$m" 2>/dev/null | grep -vc '^[0-9]*:legacy_permissions:' || true)
  assert_eq "0" "$bad" "$(basename "$(dirname "$m")")/aether.plugin names the old spelling only as legacy_permissions"
done

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
mkdir -p "$HU/.aether"
printf 'version=0.1.0\nscope=global\n' > "$HU/.aether/manifest"

env HOME="$HU" bash "$REPO/install.sh" --global --no-bonsai >"$HU/out.log" 2>&1
e=$?
assert_exit 0 "$e" "upgrade over a 0.1.0 install exits 0"
for c in $OLD_NAMES; do
  [ -f "$HU/.claude/commands/$c" ] && fail "pruned $c" || pass "pruned $c"
done
for c in critique-plan.md critique-diff.md draft-commit.md; do
  [ -f "$HU/.claude/commands/$c" ] && pass "installed $c" || fail "installed $c"
done
assert_contains "$(cat "$HU/.aether/manifest")" "commands=" \
  "the manifest now records what it shipped"

# A hand-edited command must not vanish silently.
suite "prune preserves user edits"
HE=$(new_home)
mkdir -p "$HE/.claude/commands"
printf 'MY OWN HEAVILY EDITED VERSION\n' > "$HE/.claude/commands/cairn-commit.md"
cp "$REPO/plugins/cairn/.claude/commands/draft-pr.md" "$HE/.claude/commands/cairn-pr.md" 2>/dev/null || true
mkdir -p "$HE/.aether"
printf 'version=0.1.0\nscope=global\n' > "$HE/.aether/manifest"
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
  assert_contains "$first_val" "\"Bash\"" "all backends write the base permissions"
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
