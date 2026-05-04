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

echo "==> Registering bonsai-first prompt hook in ~/.claude/settings.json (user scope)"
NUDGE_PROMPT="If the bash command uses grep, sed, awk, or find on .py/.ts/.tsx files, use a bonsai AST tool instead (pyfindrefs, tsfindrefs, pyrename, tsrename, pygrep, pyfindunused…). Only fall back to text tools if no bonsai tool covers the operation."
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

# Remove any legacy bonsai Bash enforcement hook (command type) or prompt nudge, then re-add.
pre[:] = [
    h for h in pre
    if not (h.get("matcher") == "Bash" and
            any(
                "enforce-bonsai" in hook.get("command", "") or
                "bonsai AST tool" in hook.get("prompt", "")
                for hook in h.get("hooks", [])
            ))
]
pre.append({
    "matcher": "Bash",
    "hooks": [{"type": "prompt", "prompt": "$NUDGE_PROMPT"}]
})

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("  Prompt hook registered for Bash")
PYEOF

echo ""
echo "Done. Restart Claude Code to pick up new skills and hooks."
echo "Run scripts/test.sh to verify everything works."
echo "Run scripts/clean.sh to remove local build artifacts and unregister."
