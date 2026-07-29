#!/bin/bash
set -e

MODE="local"
WITH_CLAUDE_MD=false
WITH_PROACTIVE=true
SUITE=false

for arg in "$@"; do
  case "$arg" in
    global)              MODE="global" ;;
    --claude-md)         WITH_CLAUDE_MD=true ;;
    --no-proactive)      WITH_PROACTIVE=false ;;
    # Invoked by the aether suite installer: enforce-suite.sh supersedes the
    # PreToolUse hook and templates/CLAUDE.md supersedes the temper block.
    --suite)             SUITE=true ;;
  esac
done

if [ "$MODE" = "global" ]; then
  COMMANDS_DIR="$HOME/.claude/commands"
  SETTINGS_DIR="$HOME/.claude"
  CLAUDE_FILE="$HOME/.claude/CLAUDE.md"
else
  COMMANDS_DIR=".claude/commands"
  SETTINGS_DIR=".claude"
  CLAUDE_FILE="./CLAUDE.md"
fi

# BASH_SOURCE rather than $0 so the script resolves its own assets when invoked
# as `bash plugins/temper/install.sh` from the repo root.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Adds permissions, and registers the PreToolUse hook unless hook_path is empty
# (suite mode registers enforce-suite.sh instead).
_json_add_perms_and_hook() {
  local file="$1"
  local hook_path="$2"
  local lockfile="${file}.lock"

  # Protect the read-modify-write cycle against concurrent installs (e.g. a suite installer
  # running all plugins in parallel).  flock is native on Linux and available on macOS via
  # Homebrew's util-linux; falls back to unguarded execution when not present.
  (
    if command -v flock &>/dev/null; then
      exec 9>"$lockfile" && flock -x 9 || true
    fi

    if command -v python3 &>/dev/null; then
      python3 - "$file" "$hook_path" <<'PYEOF'
import json, sys
f, hook_path = sys.argv[1], sys.argv[2]
with open(f) as fh: s = json.load(fh)
allow = s.setdefault("permissions", {}).setdefault("allow", [])
for p in ["Read", "Write", "Bash"]:
    if p not in allow: allow.append(p)
hooks = s.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])
existing = [h for h in pre if isinstance(h, dict) and "temper" in str(h.get("hooks", []))]
if hook_path and not existing:
    pre.insert(0, {
        "matcher": "Bash",
        "hooks": [{
            "type": "command",
            "command": hook_path
        }]
    })
print(json.dumps(s, indent=2))
PYEOF
    elif command -v node &>/dev/null; then
      node - "$file" "$hook_path" <<'JSEOF'
const f = process.argv[2], hookPath = process.argv[3];
const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
s.permissions = s.permissions || {};
s.permissions.allow = s.permissions.allow || [];
for (const p of ["Read", "Write", "Bash"]) {
  if (!s.permissions.allow.includes(p)) s.permissions.allow.push(p);
}
s.hooks = s.hooks || {};
s.hooks.PreToolUse = s.hooks.PreToolUse || [];
const existing = s.hooks.PreToolUse.filter(h => h && JSON.stringify(h).includes("temper"));
if (hookPath && !existing.length) {
  s.hooks.PreToolUse.unshift({ matcher: "Bash", hooks: [{ type: "command", command: hookPath }] });
}
process.stdout.write(JSON.stringify(s, null, 2) + "\n");
JSEOF
    elif command -v jq &>/dev/null; then
      jq --arg hp "$hook_path" '
        .permissions.allow |= (. + ["Read","Write","Bash"] | unique) |
        (if $hp == "" then .
         else .hooks.PreToolUse |= (. // [] | if any(tostring | contains("temper")) then . else [{"matcher":"Bash","hooks":[{"type":"command","command":$hp}]}] + . end)
         end)
      ' "$file"
    else
      return 1
    fi
  )
  rm -f "$lockfile" 2>/dev/null || true
}

# Install command file
mkdir -p "$COMMANDS_DIR"
# Commands this plugin used to ship under other names. The suite installer prunes
# generically from the manifest, but a standalone `bash plugins/temper/install.sh`
# has no manifest to consult, so it cleans up its own history. An orphan here is
# not inert — it stays in the command palette and still runs the stale copy.
LEGACY_COMMANDS="temper.md"
for _old in $LEGACY_COMMANDS; do
  if [ -f "$COMMANDS_DIR/$_old" ]; then
    # Never fatal under `set -e` — see the note in aether's install.sh.
    if cp "$COMMANDS_DIR/$_old" "$COMMANDS_DIR/$_old.bak" 2>/dev/null \
       && rm "$COMMANDS_DIR/$_old" 2>/dev/null; then
      echo "✓ Removed superseded $COMMANDS_DIR/$_old (kept a .bak)"
    else
      echo "! Could not remove superseded $COMMANDS_DIR/$_old — remove it by hand"
    fi
  fi
done

ALL_COMMANDS="critique-diff.md critique-pr.md"
for name in $ALL_COMMANDS; do
  cp "$REPO_DIR/.claude/commands/$name" "$COMMANDS_DIR/$name"
done
echo "✓ /critique-diff and /critique-pr installed to $COMMANDS_DIR"

# Install hook. Skipped under --suite: enforce-suite.sh sources this gate
# directly from ~/.local/share/aether/gates/, so registering it here too would
# double-fire every temper check. An empty HOOK_PATH tells the JSON helper
# below to add permissions only.
HOOK_PATH=""
if [ "$SUITE" = false ]; then
  HOOKS_DEST="$SETTINGS_DIR/hooks"
  mkdir -p "$HOOKS_DEST"
  cp "$REPO_DIR/hooks/enforce-temper.sh" "$HOOKS_DEST/enforce-temper.sh"
  chmod +x "$HOOKS_DEST/enforce-temper.sh"
  HOOK_PATH="$HOOKS_DEST/enforce-temper.sh"
  echo "✓ enforce-temper.sh installed to $HOOK_PATH"
fi

# Inject permissions + hook into settings.json
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
mkdir -p "$SETTINGS_DIR"
if [ ! -f "$SETTINGS_FILE" ]; then
  printf '{\n  "permissions": {\n    "allow": ["Read", "Write", "Bash"]\n  }\n}\n' > "$SETTINGS_FILE"
  echo "✓ Created $SETTINGS_FILE with permissions"
fi

if _json_add_perms_and_hook "$SETTINGS_FILE" "$HOOK_PATH" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"; then
  if [ -n "$HOOK_PATH" ]; then
    echo "✓ Permissions (Read, Write, Bash) and enforce-temper hook added to $SETTINGS_FILE"
  else
    echo "✓ Permissions (Read, Write, Bash) added to $SETTINGS_FILE"
  fi
else
  rm -f "$SETTINGS_FILE.tmp"
  echo "  Could not update $SETTINGS_FILE automatically (install python3, node, or jq)."
  echo "  Manually add permissions${HOOK_PATH:+ and register the hook at: $HOOK_PATH}"
fi

# Optionally inject code review discipline into CLAUDE.md
if [ "$WITH_CLAUDE_MD" = true ] && [ "$SUITE" = false ]; then
  MARKER="<!-- temper:start -->"

  if [ "$WITH_PROACTIVE" = false ]; then
    echo "  Skipping CLAUDE.md injection (--no-proactive flag set)"
  elif [ -f "$CLAUDE_FILE" ] && grep -q "$MARKER" "$CLAUDE_FILE"; then
    echo "✓ $CLAUDE_FILE already contains temper section — skipped"
  else
    {
      printf "\n"
      cat "$REPO_DIR/templates/CLAUDE.md"
    } >> "$CLAUDE_FILE"
    echo "✓ Code review discipline added to $CLAUDE_FILE"
  fi
fi

# Install temper CLI for global mode
if [ "$MODE" = "global" ]; then
  CLI_DIR="$HOME/.local/bin"
  mkdir -p "$CLI_DIR"
  cp "$REPO_DIR/bin/temper" "$CLI_DIR/temper"
  chmod +x "$CLI_DIR/temper"
  echo "✓ temper CLI installed to $CLI_DIR/temper"

  if ! echo "$PATH" | grep -q "$CLI_DIR"; then
    echo "  Note: add $CLI_DIR to your PATH to use the 'temper' command"
  fi
fi

echo ""
if [ "$MODE" = "global" ]; then
  echo "Available in all Claude Code projects. Restart Claude Code to activate."
  echo ""
  echo "Run 'temper status' to verify your install."
else
  echo "Available in this project. Restart Claude Code to activate."
  echo ""
  echo "Tips:"
  echo "  Global install:                   bash install.sh global"
  echo "  With proactive CLAUDE.md rules:   bash install.sh --claude-md"
  echo "  Global + proactive rules:         bash install.sh global --claude-md"
  echo "  Disable proactive suggestions:    bash install.sh --claude-md --no-proactive"
  echo "  Whole suite instead of just this: bash ../../install.sh --global --claude-md"
fi
