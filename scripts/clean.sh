#!/usr/bin/env bash
set -e

echo "==> Removing bonsai skills from ~/.claude/skills/"
for skill_dir in skills/*/; do
  skill_name=$(basename "$skill_dir")
  rm -rf "$HOME/.claude/skills/$skill_name"
  echo "  Removed: $skill_name"
done

echo "==> Removing enforcement hook from ~/.claude/settings.json"
python3 - <<PYEOF
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
try:
    with open(settings_path) as f:
        settings = json.load(f)
except FileNotFoundError:
    print("  ~/.claude/settings.json not found, nothing to remove.")
    exit(0)

pre = settings.get("hooks", {}).get("PreToolUse", [])
before = len(pre)
settings["hooks"]["PreToolUse"] = [
    h for h in pre
    if not (h.get("matcher") == "Bash" and
            any("enforce-bonsai" in hook.get("command", "") for hook in h.get("hooks", [])))
]
removed = before - len(settings["hooks"]["PreToolUse"])

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(f"  Removed {removed} hook entry(ies).")
PYEOF

echo "==> Removing Python virtual environment"
rm -rf py/.venv

echo "==> Removing TypeScript build output"
rm -rf ts/dist ts/node_modules

echo ""
echo "Done. Run scripts/setup.sh to set up again."
echo "To also remove globally-registered MCP servers:"
echo "  claude mcp remove bonsai-py --scope user"
echo "  claude mcp remove bonsai-ts --scope user"
