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

# Remove command file
if [ -f "$COMMANDS_DIR/cairn.md" ]; then
  rm "$COMMANDS_DIR/cairn.md"
  echo "✓ Removed $COMMANDS_DIR/cairn.md"
else
  echo "  $COMMANDS_DIR/cairn.md not found"
fi

# Remove cairn section from CLAUDE.md
if [ "$WITH_CLAUDE_MD" = true ]; then
  if [ -f "$CLAUDE_FILE" ] && grep -q "<!-- cairn:start -->" "$CLAUDE_FILE"; then
    awk '/<!-- cairn:start -->/{skip=1} !skip{print} /<!-- cairn:end -->/{skip=0}' \
      "$CLAUDE_FILE" > "$CLAUDE_FILE.tmp" && mv "$CLAUDE_FILE.tmp" "$CLAUDE_FILE"
    echo "✓ Removed cairn section from $CLAUDE_FILE"
  else
    echo "  No cairn section found in $CLAUDE_FILE"
  fi
fi

# Remove CLI binary for global mode
if [ "$MODE" = "global" ]; then
  CLI_BIN="$HOME/.local/bin/cairn"
  if [ -f "$CLI_BIN" ]; then
    rm "$CLI_BIN"
    echo "✓ Removed $CLI_BIN"
  else
    echo "  $CLI_BIN not found"
  fi
fi

echo ""
echo "Restart Claude Code to apply changes."
