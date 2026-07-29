#!/bin/bash
set -e

MODE="local"
WITH_CLAUDE_MD=false

for arg in "$@"; do
  case "$arg" in
    global) MODE="global" ;;
    --claude-md) WITH_CLAUDE_MD=true ;;
  esac
done

if [ "$MODE" = "global" ]; then
  COMMANDS_DIR="$HOME/.claude/commands"
  CLAUDE_FILE="$HOME/.claude/CLAUDE.md"
else
  COMMANDS_DIR=".claude/commands"
  CLAUDE_FILE="./CLAUDE.md"
fi

ALL_COMMANDS="draft-commit.md draft-pr.md draft-changelog.md draft-summary.md"

# Remove command files
for name in $ALL_COMMANDS; do
  if [ -f "$COMMANDS_DIR/$name" ]; then
    rm "$COMMANDS_DIR/$name"
    echo "✓ Removed $COMMANDS_DIR/$name"
  else
    echo "  $COMMANDS_DIR/$name not found"
  fi
done

# Remove cairn and docs sections from CLAUDE.md
if [ "$WITH_CLAUDE_MD" = true ]; then
  for marker in "cairn" "docs"; do
    if [ -f "$CLAUDE_FILE" ] && grep -q "<!-- ${marker}:start -->" "$CLAUDE_FILE"; then
      awk "/<!-- ${marker}:start -->/{skip=1} !skip{print} /<!-- ${marker}:end -->/{skip=0}" \
        "$CLAUDE_FILE" > "$CLAUDE_FILE.tmp" && mv "$CLAUDE_FILE.tmp" "$CLAUDE_FILE"
      echo "✓ Removed ${marker} section from $CLAUDE_FILE"
    else
      echo "  No ${marker} section found in $CLAUDE_FILE"
    fi
  done
fi

# Remove CLI binary and hook for global mode
if [ "$MODE" = "global" ]; then
  CLI_BIN="$HOME/.local/bin/cairn"
  if [ -f "$CLI_BIN" ]; then
    rm "$CLI_BIN"
    echo "✓ Removed $CLI_BIN"
  else
    echo "  $CLI_BIN not found"
  fi

  HOOK_DIR="$HOME/.local/share/cairn"
  HOOK_FILE="$HOOK_DIR/enforce-cairn.sh"
  POST_HOOK_FILE="$HOOK_DIR/post-cairn.sh"
  GLOBAL_SETTINGS="$HOME/.claude/settings.json"

  if [ -f "$HOOK_FILE" ]; then
    rm "$HOOK_FILE"
    echo "✓ Removed $HOOK_FILE"
  fi

  if [ -f "$POST_HOOK_FILE" ]; then
    rm "$POST_HOOK_FILE"
    echo "✓ Removed $POST_HOOK_FILE"
  fi

  # Remove PreToolUse hook entry from settings.json
  if command -v python3 &>/dev/null && [ -f "$GLOBAL_SETTINGS" ]; then
    python3 - "$GLOBAL_SETTINGS" "$HOOK_FILE" <<'PYEOF' > "$GLOBAL_SETTINGS.tmp" \
      && mv "$GLOBAL_SETTINGS.tmp" "$GLOBAL_SETTINGS" \
      && echo "✓ PreToolUse hook entry removed from $GLOBAL_SETTINGS"
import json, sys
f, hook_path = sys.argv[1], sys.argv[2]
with open(f) as fh: s = json.load(fh)
pre = s.get("hooks", {}).get("PreToolUse", [])
for entry in pre:
    if entry.get("matcher") == "Bash":
        entry["hooks"] = [h for h in entry.get("hooks", []) if h.get("command") != hook_path]
print(json.dumps(s, indent=2))
PYEOF

    # Remove PostToolUse hook entry from settings.json
    python3 - "$GLOBAL_SETTINGS" "$POST_HOOK_FILE" <<'PYEOF' > "$GLOBAL_SETTINGS.tmp" \
      && mv "$GLOBAL_SETTINGS.tmp" "$GLOBAL_SETTINGS" \
      && echo "✓ PostToolUse hook entry removed from $GLOBAL_SETTINGS"
import json, sys
f, hook_path = sys.argv[1], sys.argv[2]
with open(f) as fh: s = json.load(fh)
post = s.get("hooks", {}).get("PostToolUse", [])
for entry in post:
    if entry.get("matcher") == "Bash|Write|Edit":
        entry["hooks"] = [h for h in entry.get("hooks", []) if h.get("command") != hook_path]
print(json.dumps(s, indent=2))
PYEOF
  fi
fi

echo ""
echo "Restart Claude Code to apply changes."
