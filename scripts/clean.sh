#!/usr/bin/env bash
set -e

echo "==> Removing bonsai enforcement hook from ~/.claude.json"
python3 - <<PYEOF
import json, os

config_path = os.path.expanduser("~/.claude.json")
try:
    with open(config_path) as f:
        config = json.load(f)
except FileNotFoundError:
    print("  ~/.claude.json not found, nothing to remove.")
    exit(0)

pre = config.get("hooks", {}).get("PreToolUse", [])
before = len(pre)
config["hooks"]["PreToolUse"] = [
    h for h in pre
    if not (h.get("matcher") == "Bash" and
            any("enforce-bonsai" in hook.get("command", "") for hook in h.get("hooks", [])))
]
removed = before - len(config["hooks"]["PreToolUse"])

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)
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
