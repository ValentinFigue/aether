#!/bin/bash
set -e

MODE="local"
CLEAN_CLAUDE_MD=false

for arg in "$@"; do
  case "$arg" in
    global) MODE="global" ;;
    --claude-md) CLEAN_CLAUDE_MD=true ;;
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

_json_remove_hook() {
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 - "$file" <<'PYEOF'
import json, sys
f = sys.argv[1]
with open(f) as fh: s = json.load(fh)
pre = s.get("hooks", {}).get("PreToolUse", [])
s.setdefault("hooks", {})["PreToolUse"] = [
    e for e in pre
    if not (isinstance(e, dict) and
            any("enforce-whetstone" in str(h.get("command", "")) for h in e.get("hooks", [])))
]
print(json.dumps(s, indent=2))
PYEOF
  elif command -v node &>/dev/null; then
    node - "$file" <<'JSEOF'
const f = process.argv[2];
const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
if (s.hooks && s.hooks.PreToolUse) {
  s.hooks.PreToolUse = s.hooks.PreToolUse.filter(e =>
    !(e.hooks && e.hooks.some(h => h.command && h.command.includes("enforce-whetstone")))
  );
}
process.stdout.write(JSON.stringify(s, null, 2) + "\n");
JSEOF
  elif command -v jq &>/dev/null; then
    jq '.hooks.PreToolUse = [(.hooks.PreToolUse // [])[] | select(.hooks[]?.command | strings | contains("enforce-whetstone") | not)]' "$file"
  else
    return 1
  fi
}

_json_remove_perms() {
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 - "$file" <<'PYEOF'
import json, sys
f = sys.argv[1]
with open(f) as fh: s = json.load(fh)
allow = s.get("permissions", {}).get("allow", [])
s.setdefault("permissions", {})["allow"] = [p for p in allow if p not in ("Read", "Write")]
print(json.dumps(s, indent=2))
PYEOF
  elif command -v node &>/dev/null; then
    node - "$file" <<'JSEOF'
const f = process.argv[2];
const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
if (s.permissions && s.permissions.allow) {
  s.permissions.allow = s.permissions.allow.filter(function(p) { return p !== "Read" && p !== "Write"; });
}
process.stdout.write(JSON.stringify(s, null, 2) + "\n");
JSEOF
  elif command -v jq &>/dev/null; then
    jq '.permissions.allow |= map(select(. != "Read" and . != "Write"))' "$file"
  else
    return 1
  fi
}

HOOKS_DIR="$SETTINGS_DIR/hooks"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
REMOVED=0

# Remove hook file
HOOK_FILE="$HOOKS_DIR/enforce-whetstone.sh"
if [ -f "$HOOK_FILE" ]; then
  rm "$HOOK_FILE"
  echo "✓ Removed $HOOK_FILE"
  REMOVED=$((REMOVED + 1))
else
  echo "  $HOOK_FILE not found — skipped"
fi

# Remove hook registration from settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "  $SETTINGS_FILE not found — skipped hook deregistration"
elif _json_remove_hook "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"; then
  echo "✓ PreToolUse hook removed from $SETTINGS_FILE"
  REMOVED=$((REMOVED + 1))
else
  echo "  Could not update $SETTINGS_FILE automatically."
  echo "  Remove the enforce-whetstone entry from hooks.PreToolUse manually."
fi

# Remove whetstone CLI binary (global only)
if [ "$MODE" = "global" ]; then
  CLI="$HOME/.local/bin/whetstone"
  if [ -f "$CLI" ]; then
    rm "$CLI"
    echo "✓ Removed $CLI"
    REMOVED=$((REMOVED + 1))
  else
    echo "  $CLI not found — skipped"
  fi
fi

# Remove command file
COMMAND_FILE="$COMMANDS_DIR/autocritic.md"
if [ -f "$COMMAND_FILE" ]; then
  rm "$COMMAND_FILE"
  echo "✓ Removed $COMMAND_FILE"
  REMOVED=$((REMOVED + 1))
else
  echo "  $COMMAND_FILE not found — skipped"
fi

# Remove Read + Write permissions from settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "  $SETTINGS_FILE not found — skipped"
elif _json_remove_perms "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"; then
  echo "✓ Permissions (Read, Write) removed from $SETTINGS_FILE"
  REMOVED=$((REMOVED + 1))
else
  echo "  Could not update $SETTINGS_FILE automatically."
  echo "  Remove \"Read\" and \"Write\" from permissions.allow manually."
fi

# Remove whetstone section from CLAUDE.md
if [ "$CLEAN_CLAUDE_MD" = true ]; then
  if [ -f "$CLAUDE_FILE" ] && grep -q "<!-- whetstone:start -->" "$CLAUDE_FILE"; then
    awk '/<!-- whetstone:start -->/{skip=1} !skip{print} /<!-- whetstone:end -->/{skip=0}' \
      "$CLAUDE_FILE" > "$CLAUDE_FILE.tmp" && mv "$CLAUDE_FILE.tmp" "$CLAUDE_FILE"
    echo "✓ Removed whetstone section from $CLAUDE_FILE"
    REMOVED=$((REMOVED + 1))
  else
    echo "  No whetstone section found in $CLAUDE_FILE — skipped"
  fi
fi

echo ""
if [ "$REMOVED" -gt 0 ]; then
  echo "Done. Restart Claude Code to apply changes."
else
  echo "Nothing to remove."
fi
