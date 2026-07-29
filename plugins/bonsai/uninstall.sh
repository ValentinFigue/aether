#!/usr/bin/env bash
set -e

# ── options ────────────────────────────────────────────────────────────────────
REMOVE_CLAUDE_MD=false
for arg in "$@"; do
  case "$arg" in
    --claude-md) REMOVE_CLAUDE_MD=true ;;
    *) echo "Unknown option: $arg"; echo "Usage: $0 [--claude-md]"; exit 1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# ── helpers ────────────────────────────────────────────────────────────────────
check_ok()   { echo "  ✓ $*"; }
check_skip() { echo "  - $*"; }

removed=0

# ── MCP server entries ─────────────────────────────────────────────────────────
echo "==> Removing MCP servers from ~/.claude.json"

python3 - <<'PYEOF'
import json, os

claude_json_path = os.path.expanduser("~/.claude.json")
if not os.path.exists(claude_json_path):
    print("  - ~/.claude.json not found, nothing to remove")
    exit(0)

try:
    with open(claude_json_path) as f:
        data = json.load(f)
except json.JSONDecodeError:
    print("  - ~/.claude.json unreadable, skipping")
    exit(0)

servers = data.get("mcpServers", {})
removed = []
for key in ["bonsai-py", "bonsai-ts"]:
    if key in servers:
        del servers[key]
        removed.append(key)

tmp = claude_json_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, claude_json_path)

if removed:
    for k in removed:
        print(f"  ✓ {k} removed")
else:
    print("  - no bonsai MCP entries found")
PYEOF

# ── permissions ────────────────────────────────────────────────────────────────
echo ""
echo "==> Removing MCP permissions from ~/.claude/settings.json"

python3 - <<'PYEOF'
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
if not os.path.exists(settings_path):
    print("  - ~/.claude/settings.json not found, nothing to remove")
    exit(0)

try:
    with open(settings_path) as f:
        settings = json.load(f)
except json.JSONDecodeError:
    print("  - ~/.claude/settings.json unreadable, skipping")
    exit(0)

allow = settings.get("permissions", {}).get("allow", [])
before = len(allow)
# Both spellings: the hyphenated one that works, and the underscore one older
# installs wrote before the mismatch was found.
settings.setdefault("permissions", {})["allow"] = [
    e for e in allow if e not in ("mcp__bonsai-py__*", "mcp__bonsai-ts__*",
                                  "mcp__bonsai_py__*", "mcp__bonsai_ts__*")
]
removed_count = before - len(settings["permissions"]["allow"])

tmp = settings_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(tmp, settings_path)

if removed_count:
    print(f"  ✓ {removed_count} bonsai permission(s) removed")
else:
    print("  - no bonsai permissions found")
PYEOF

# ── hooks ──────────────────────────────────────────────────────────────────────
echo ""
echo "==> Removing bonsai hooks from ~/.claude/settings.json"

python3 - <<'PYEOF'
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
if not os.path.exists(settings_path):
    print("  - ~/.claude/settings.json not found, nothing to remove")
    exit(0)

try:
    with open(settings_path) as f:
        settings = json.load(f)
except json.JSONDecodeError:
    print("  - ~/.claude/settings.json unreadable, skipping")
    exit(0)

removed_count = 0

# PreToolUse — Bash nudge hook
pre = settings.get("hooks", {}).get("PreToolUse", [])
before = len(pre)
settings.setdefault("hooks", {})["PreToolUse"] = [
    h for h in pre
    if not (
        h.get("matcher") == "Bash" and
        any(
            (hook.get("type") == "prompt" and "bonsai AST tool" in hook.get("prompt", "")) or
            (hook.get("type") == "command" and "enforce-bonsai" in hook.get("command", ""))
            for hook in h.get("hooks", [])
        )
    )
]
removed_count += before - len(settings["hooks"]["PreToolUse"])

# PostToolUse — reference-drift hook
post = settings.get("hooks", {}).get("PostToolUse", [])
before = len(post)
settings.setdefault("hooks", {})["PostToolUse"] = [
    h for h in post
    if not (
        h.get("matcher") in ("Write|Edit|MultiEdit", "Write", "Edit", "MultiEdit") and
        any("post-bonsai" in hook.get("command", "") for hook in h.get("hooks", []))
    )
]
removed_count += before - len(settings["hooks"]["PostToolUse"])

tmp = settings_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(tmp, settings_path)

if removed_count:
    print(f"  ✓ {removed_count} bonsai hook(s) removed")
else:
    print("  - no bonsai hooks found")
PYEOF

# ── skills ─────────────────────────────────────────────────────────────────────
echo ""
echo "==> Removing bonsai skills from ~/.claude/skills/"
for skill_dir in "$REPO_ROOT/skills/"/*/; do
  skill_name=$(basename "$skill_dir")
  target="$HOME/.claude/skills/$skill_name"
  if [ -d "$target" ]; then
    rm -rf "$target"
    check_ok "skill removed: $skill_name"
    removed=$((removed + 1))
  else
    check_skip "skill not found: $skill_name"
  fi
done

# ── CLI binary ─────────────────────────────────────────────────────────────────
echo ""
echo "==> Removing ~/.local/bin/bonsai"
if [ -L "$HOME/.local/bin/bonsai" ] || [ -f "$HOME/.local/bin/bonsai" ]; then
  rm -f "$HOME/.local/bin/bonsai"
  check_ok "~/.local/bin/bonsai removed"
  removed=$((removed + 1))
else
  check_skip "~/.local/bin/bonsai not found"
fi

# ── CLAUDE.md section ──────────────────────────────────────────────────────────
if [ "$REMOVE_CLAUDE_MD" = true ]; then
  echo ""
  echo "==> Removing bonsai section from ~/.claude/CLAUDE.md"

  CLAUDE_MD_PATH="$HOME/.claude/CLAUDE.md"
  if [ ! -f "$CLAUDE_MD_PATH" ]; then
    check_skip "~/.claude/CLAUDE.md not found"
  elif ! grep -q "<!-- bonsai:start -->" "$CLAUDE_MD_PATH"; then
    check_skip "bonsai section not present"
  else
    awk '/<!-- bonsai:start -->/{skip=1} skip{if(/<!-- bonsai:end -->/) {skip=0; next} next} !skip' \
      "$CLAUDE_MD_PATH" > "$CLAUDE_MD_PATH.tmp" && mv "$CLAUDE_MD_PATH.tmp" "$CLAUDE_MD_PATH"
    check_ok "bonsai section removed from $CLAUDE_MD_PATH"
    removed=$((removed + 1))
  fi
fi

# ── done ───────────────────────────────────────────────────────────────────────
echo ""
echo "Done. Restart Claude Code to apply the changes."
if [ "$REMOVE_CLAUDE_MD" = false ]; then
  echo "Tip: run './uninstall.sh --claude-md' to also remove the bonsai section from ~/.claude/CLAUDE.md"
fi
