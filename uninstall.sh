#!/bin/bash
set -e

MODE="local"
WITH_CLAUDE_MD=false

for arg in "$@"; do
  case "$arg" in
    global|--global) MODE="global" ;;
    --claude-md)     WITH_CLAUDE_MD=true ;;
  esac
done

if [ "$MODE" = "global" ]; then
  SETTINGS_FILE="$HOME/.claude/settings.json"
  HOOK_DIR="$HOME/.local/share/aether"
  CLI="$HOME/.local/bin/aether"
  CLAUDE_FILE="$HOME/.claude/CLAUDE.md"
  MANIFEST="$HOME/.claude/aether.manifest"
else
  SETTINGS_FILE=".claude/settings.json"
  HOOK_DIR=".claude/hooks"
  CLI=""
  CLAUDE_FILE="./CLAUDE.md"
  MANIFEST=".claude/aether.manifest"
fi

# Remove enforce-suite.sh and any stale per-plugin hooks from settings.json
if [ -f "$SETTINGS_FILE" ] && command -v python3 &>/dev/null; then
  python3 - "$SETTINGS_FILE" <<'PYEOF' > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
import json, sys
f = sys.argv[1]
with open(f) as fh: s = json.load(fh)
STALE = ["enforce-suite", "enforce-cairn", "enforce-temper", "enforce-whetstone",
         "enforce-bonsai", "post-cairn", "post-bonsai"]
for phase in ("PreToolUse", "PostToolUse"):
    entries = s.get("hooks", {}).get(phase, [])
    for entry in entries:
        entry["hooks"] = [
            h for h in entry.get("hooks", [])
            if not any(kw in h.get("command", "") for kw in STALE)
        ]
    s.get("hooks", {})[phase] = [e for e in entries if e.get("hooks")]
print(json.dumps(s, indent=2))
PYEOF
  printf '✓ Removed aether hooks from %s\n' "$SETTINGS_FILE"
elif [ -f "$SETTINGS_FILE" ]; then
  printf '  Could not update %s automatically (install python3).\n' "$SETTINGS_FILE"
  printf '  Remove the enforce-suite.sh PreToolUse hook manually.\n'
fi

# Remove enforce-suite.sh from hook directory
if [ -f "$HOOK_DIR/enforce-suite.sh" ]; then
  rm "$HOOK_DIR/enforce-suite.sh"
  printf '✓ Removed %s/enforce-suite.sh\n' "$HOOK_DIR"
fi

# Remove aether CLI (global only)
if [ -n "$CLI" ] && [ -f "$CLI" ]; then
  rm "$CLI"
  printf '✓ Removed %s\n' "$CLI"
fi

# Remove CLAUDE.md block
if [ "$WITH_CLAUDE_MD" = true ] && [ -f "$CLAUDE_FILE" ]; then
  for marker in "aether" "cairn" "temper" "whetstone" "bonsai"; do
    if grep -q "<!-- ${marker}:start -->" "$CLAUDE_FILE" 2>/dev/null; then
      awk "/<!-- ${marker}:start -->/{skip=1} !skip{print} /<!-- ${marker}:end -->/{skip=0}" \
        "$CLAUDE_FILE" > "$CLAUDE_FILE.tmp" && mv "$CLAUDE_FILE.tmp" "$CLAUDE_FILE"
      printf '✓ Removed %s section from %s\n' "$marker" "$CLAUDE_FILE"
    fi
  done
fi

# Remove manifest
[ -f "$MANIFEST" ] && rm "$MANIFEST" && printf '✓ Removed %s\n' "$MANIFEST"

printf '\n'
printf 'aether removed.\n'
[ "$MODE" = "local" ] && printf 'Note: aether CLI (~/.local/bin/aether) is only removed on global uninstall.\n'
printf 'Plugins (bonsai, whetstone, temper, cairn) remain installed for standalone use.\n'
printf 'Restart Claude Code to apply changes.\n'
