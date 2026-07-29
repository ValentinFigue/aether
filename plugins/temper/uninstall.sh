#!/bin/bash
set -e

MODE="local"
CLEAN_CLAUDE_MD=false

for arg in "$@"; do
  case "$arg" in
    global)       MODE="global" ;;
    --claude-md)  CLEAN_CLAUDE_MD=true ;;
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

_json_remove_perms_and_hook() {
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 - "$file" <<'PYEOF'
import json, sys
f = sys.argv[1]
with open(f) as fh: s = json.load(fh)
allow = s.get("permissions", {}).get("allow", [])
s.setdefault("permissions", {})["allow"] = [p for p in allow if p not in ("Read", "Write", "Bash")]
pre = s.get("hooks", {}).get("PreToolUse", [])
s.setdefault("hooks", {})["PreToolUse"] = [
    h for h in pre
    if not (isinstance(h, dict) and "temper" in str(h.get("hooks", [])))
]
print(json.dumps(s, indent=2))
PYEOF
  elif command -v node &>/dev/null; then
    node - "$file" <<'JSEOF'
const f = process.argv[2];
const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
if (s.permissions && s.permissions.allow) {
  s.permissions.allow = s.permissions.allow.filter(p => !["Read","Write","Bash"].includes(p));
}
if (s.hooks && s.hooks.PreToolUse) {
  s.hooks.PreToolUse = s.hooks.PreToolUse.filter(h => !JSON.stringify(h).includes("temper"));
}
process.stdout.write(JSON.stringify(s, null, 2) + "\n");
JSEOF
  elif command -v jq &>/dev/null; then
    jq '
      .permissions.allow |= map(select(. != "Read" and . != "Write" and . != "Bash")) |
      .hooks.PreToolUse |= map(select(tostring | contains("temper") | not))
    ' "$file"
  else
    return 1
  fi
}

REMOVED=0

# Remove temper CLI binary (global only)
if [ "$MODE" = "global" ]; then
  CLI="$HOME/.local/bin/temper"
  if [ -f "$CLI" ]; then
    rm "$CLI"
    echo "✓ Removed $CLI"
    REMOVED=$((REMOVED + 1))
  else
    echo "  $CLI not found — skipped"
  fi
fi

# Remove hook
HOOK_FILE="$SETTINGS_DIR/hooks/enforce-temper.sh"
if [ -f "$HOOK_FILE" ]; then
  rm "$HOOK_FILE"
  echo "✓ Removed $HOOK_FILE"
  REMOVED=$((REMOVED + 1))
fi

# Remove command file
ALL_COMMANDS="critique-diff.md critique-pr.md"
if [ -f "$COMMAND_FILE" ]; then
  rm "$COMMAND_FILE"
  echo "✓ Removed $COMMAND_FILE"
  REMOVED=$((REMOVED + 1))
else
  echo "  $COMMAND_FILE not found — skipped"
fi

# Remove permissions and hook from settings.json
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "  $SETTINGS_FILE not found — skipped"
elif _json_remove_perms_and_hook "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"; then
  echo "✓ Permissions and hook entry removed from $SETTINGS_FILE"
  REMOVED=$((REMOVED + 1))
else
  echo "  Could not update $SETTINGS_FILE automatically."
  echo "  Remove the temper hook and permissions from it manually."
fi

# Remove temper section from CLAUDE.md
if [ "$CLEAN_CLAUDE_MD" = true ]; then
  if [ -f "$CLAUDE_FILE" ] && grep -q "<!-- temper:start -->" "$CLAUDE_FILE"; then
    awk '/<!-- temper:start -->/{skip=1} !skip{print} /<!-- temper:end -->/{skip=0}' \
      "$CLAUDE_FILE" > "$CLAUDE_FILE.tmp" && mv "$CLAUDE_FILE.tmp" "$CLAUDE_FILE"
    echo "✓ Removed temper section from $CLAUDE_FILE"
    REMOVED=$((REMOVED + 1))
  else
    echo "  No temper section found in $CLAUDE_FILE — skipped"
  fi
fi

echo ""
if [ "$REMOVED" -gt 0 ]; then
  echo "Done. Restart Claude Code to apply changes."
else
  echo "Nothing to remove."
fi
