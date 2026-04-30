#!/usr/bin/env bash
set -e

echo "==> Setting up Python (py/)"
cd py
uv sync
cd ..

echo "==> Setting up TypeScript (ts/)"
cd ts
npm install
npm run build
cd ..

echo "==> Registering enforcement hook in ~/.claude.json (user scope)"
HOOK_CMD="$(pwd)/.claude-plugin/hooks/enforce-bonsai.sh"
python3 - <<PYEOF
import json, os

config_path = os.path.expanduser("~/.claude.json")
try:
    with open(config_path) as f:
        config = json.load(f)
except FileNotFoundError:
    config = {}

hooks = config.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])

# Remove any existing bonsai Bash enforcement hook, then re-add with current path.
pre[:] = [
    h for h in pre
    if not (h.get("matcher") == "Bash" and
            any("enforce-bonsai" in hook.get("command", "") for hook in h.get("hooks", [])))
]
pre.append({
    "matcher": "Bash",
    "hooks": [{"type": "command", "command": "$HOOK_CMD"}]
})

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")

print("  Hook registered:", "$HOOK_CMD")
PYEOF

echo ""
echo "Done. Open this directory in Claude Code — both MCP servers should connect automatically."
echo "Restart Claude Code to pick up the new hook."
echo "Run scripts/test.sh to verify everything works."
echo "Run scripts/clean.sh to remove local build artifacts and unregister the hook."
