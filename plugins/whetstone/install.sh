#!/bin/bash
set -e

MODE="local"
WITH_CLAUDE_MD=false
SUITE=false

# Resolved from BASH_SOURCE rather than $0 so the script still finds its own
# assets when invoked as `bash plugins/whetstone/install.sh` from the repo root.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

for arg in "$@"; do
  case "$arg" in
    global) MODE="global" ;;
    --claude-md) WITH_CLAUDE_MD=true ;;
    # Invoked by the aether suite installer: enforce-suite.sh supersedes the
    # PreToolUse hook and templates/CLAUDE.md supersedes the whetstone block.
    --suite) SUITE=true ;;
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

_json_add_hook() {
  local file="$1" hook_path="$2"
  if command -v python3 &>/dev/null; then
    python3 - "$file" "$hook_path" <<'PYEOF'
import json, sys
f, hook_path = sys.argv[1], sys.argv[2]
with open(f) as fh: s = json.load(fh)
hooks = s.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])
exists = any(
    isinstance(e, dict) and
    any("enforce-whetstone" in str(h.get("command", "")) for h in e.get("hooks", []))
    for e in pre
)
if not exists:
    pre.append({
        "matcher": "Bash|Write|Edit|MultiEdit",
        "hooks": [{"type": "command", "command": hook_path}]
    })
print(json.dumps(s, indent=2))
PYEOF
  elif command -v node &>/dev/null; then
    node - "$file" "$hook_path" <<'JSEOF'
const f = process.argv[2], hookPath = process.argv[3];
const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
s.hooks = s.hooks || {};
s.hooks.PreToolUse = s.hooks.PreToolUse || [];
const exists = s.hooks.PreToolUse.some(e =>
  e.hooks && e.hooks.some(h => h.command && h.command.includes("enforce-whetstone"))
);
if (!exists) {
  s.hooks.PreToolUse.push({
    matcher: "Bash|Write|Edit|MultiEdit",
    hooks: [{ type: "command", command: hookPath }]
  });
}
process.stdout.write(JSON.stringify(s, null, 2) + "\n");
JSEOF
  elif command -v jq &>/dev/null; then
    jq --arg hp "$hook_path" '
      .hooks.PreToolUse = (
        [(.hooks.PreToolUse // [])[] | select(.hooks[]?.command | strings | contains("enforce-whetstone") | not)] +
        [{"matcher":"Bash|Write|Edit|MultiEdit","hooks":[{"type":"command","command":$hp}]}]
      )' "$file"
  else
    return 1
  fi
}

_json_add_perms() {
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 - "$file" <<'PYEOF'
import json, sys
f = sys.argv[1]
with open(f) as fh: s = json.load(fh)
allow = s.setdefault("permissions", {}).setdefault("allow", [])
for p in ["Read", "Write"]:
    if p not in allow: allow.append(p)
print(json.dumps(s, indent=2))
PYEOF
  elif command -v node &>/dev/null; then
    node - "$file" <<'JSEOF'
const f = process.argv[2];
const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
s.permissions = s.permissions || {};
s.permissions.allow = s.permissions.allow || [];
for (const p of ["Read", "Write"]) { if (!s.permissions.allow.includes(p)) s.permissions.allow.push(p); }
process.stdout.write(JSON.stringify(s, null, 2) + "\n");
JSEOF
  elif command -v jq &>/dev/null; then
    jq '.permissions.allow |= (. + ["Read","Write"] | unique)' "$file"
  else
    return 1
  fi
}

# Install command file
mkdir -p "$COMMANDS_DIR"
# Commands this plugin used to ship under other names. The suite installer prunes
# generically from the manifest, but a standalone `bash plugins/whetstone/install.sh`
# has no manifest to consult, so it cleans up its own history. An orphan here is
# not inert — it stays in the command palette and still runs the stale copy.
LEGACY_COMMANDS="autocritic.md"
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

cp "$REPO_DIR/.claude/commands/critique-plan.md" "$COMMANDS_DIR/critique-plan.md"
echo "✓ /critique-plan installed to $COMMANDS_DIR"

# Inject Read + Write permissions into settings.json
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
mkdir -p "$SETTINGS_DIR"
if [ ! -f "$SETTINGS_FILE" ]; then
  printf '{\n  "permissions": {\n    "allow": ["Read", "Write"]\n  }\n}\n' > "$SETTINGS_FILE"
  echo "✓ Permissions (Read, Write) added to $SETTINGS_FILE"
elif _json_add_perms "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"; then
  echo "✓ Permissions (Read, Write) added to $SETTINGS_FILE"
else
  echo "  Could not update $SETTINGS_FILE automatically (install python3, node, or jq)."
  echo "  Add \"Read\" and \"Write\" to permissions.allow manually."
fi

# Install and register enforce-whetstone.sh hook.
# Skipped under --suite: enforce-suite.sh sources this gate directly from
# ~/.local/share/aether/gates/, so a second registration would double-fire it.
if [ "$SUITE" = false ]; then
  HOOKS_DIR="$SETTINGS_DIR/hooks"
  if [ "$MODE" = "global" ]; then
    HOOK_PATH="$HOME/.claude/hooks/enforce-whetstone.sh"
  else
    HOOK_PATH=".claude/hooks/enforce-whetstone.sh"
  fi
  mkdir -p "$HOOKS_DIR"
  cp "$REPO_DIR/hooks/enforce-whetstone.sh" "$HOOKS_DIR/enforce-whetstone.sh"
  chmod +x "$HOOKS_DIR/enforce-whetstone.sh"
  echo "✓ enforce-whetstone.sh installed to $HOOKS_DIR"

  if _json_add_hook "$SETTINGS_FILE" "$HOOK_PATH" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"; then
    echo "✓ PreToolUse hook registered in $SETTINGS_FILE"
  else
    rm -f "$SETTINGS_FILE.tmp"
    echo "  Could not register hook in $SETTINGS_FILE automatically (install python3, node, or jq)."
    echo "  Add enforce-whetstone.sh to hooks.PreToolUse manually."
  fi
fi

# Optionally inject planning discipline into CLAUDE.md
if [ "$WITH_CLAUDE_MD" = true ] && [ "$SUITE" = false ]; then
  MARKER="<!-- whetstone:start -->"

  if [ -f "$CLAUDE_FILE" ] && grep -q "$MARKER" "$CLAUDE_FILE"; then
    echo "✓ $CLAUDE_FILE already contains whetstone section — skipped"
  else
    # templates/CLAUDE.md already carries its own start/end sentinels on the
    # first and last lines — echoing them here too produced a duplicated
    # <!-- whetstone:start --> in the output file.
    {
      printf "\n"
      cat "$REPO_DIR/templates/CLAUDE.md"
    } >> "$CLAUDE_FILE"
    echo "✓ Planning discipline added to $CLAUDE_FILE"
  fi
fi

# Install whetstone CLI for global mode
if [ "$MODE" = "global" ]; then
  CLI_DIR="$HOME/.local/bin"
  mkdir -p "$CLI_DIR"
  cp "$REPO_DIR/bin/whetstone" "$CLI_DIR/whetstone"
  chmod +x "$CLI_DIR/whetstone"
  echo "✓ whetstone CLI installed to $CLI_DIR/whetstone"

  if ! echo "$PATH" | grep -q "$CLI_DIR"; then
    echo "  Note: add $CLI_DIR to your PATH to use the 'whetstone' command"
  fi
fi

echo ""
if [ "$MODE" = "global" ]; then
  echo "Available in all Claude Code projects. Restart Claude Code to activate."
  echo ""
  echo "Run 'whetstone status' to verify your install."
else
  echo "Available in this project. Restart Claude Code to activate."
  echo ""
  echo "Tips:"
  echo "  Global install:             bash install.sh global"
  echo "  With auto-trigger:          bash install.sh --claude-md"
  echo "  Global + auto-trigger:      bash install.sh global --claude-md"
fi
