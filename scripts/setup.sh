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

echo "==> Installing skills to ~/.claude/skills/"
mkdir -p "$HOME/.claude/skills"
for skill_dir in skills/*/; do
  skill_name=$(basename "$skill_dir")
  rsync -r "$skill_dir" "$HOME/.claude/skills/$skill_name/"
  echo "  $skill_name"
done

echo "==> Registering enforcement hook in ~/.claude/settings.json (user scope)"
HOOK_CMD="$(pwd)/.claude-plugin/hooks/enforce-bonsai.sh"
python3 - <<PYEOF
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
try:
    with open(settings_path) as f:
        settings = json.load(f)
except FileNotFoundError:
    settings = {}

hooks = settings.setdefault("hooks", {})
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

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("  Hook registered:", "$HOOK_CMD")
PYEOF

echo ""
echo "Done. Restart Claude Code to pick up new skills and hooks."
echo "Run scripts/test.sh to verify everything works."
echo "Run scripts/clean.sh to remove local build artifacts and unregister."
