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

echo "==> Writing .claude/settings.json for local dev enforcement"
mkdir -p .claude
REPO_ROOT="$(pwd)"
cat > .claude/settings.json <<EOF
{
  "hooks": [
    {
      "type": "PreToolUse",
      "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "${REPO_ROOT}/.claude-plugin/hooks/enforce-bonsai.sh" }]
    },
    {
      "type": "PreToolUse",
      "matcher": "mcp__bonsai_py__(pyrename|pymove|pymovesymbol|pysignature)",
      "hooks": [{ "type": "prompt", "prompt": "You are about to run a mutating bonsai refactoring tool. Before proceeding: (1) confirm you have run with dry_run=True and reviewed the blast radius, (2) verify the target module:Symbol notation is correct, (3) ensure there are no uncommitted changes that could be lost. Summarize the planned change and confirm it is safe to proceed." }]
    },
    {
      "type": "PostToolUse",
      "matcher": "mcp__bonsai_py__(pyrename|pymove|pymovesymbol|pysignature)",
      "hooks": [{ "type": "prompt", "prompt": "A bonsai refactoring tool has finished. Remind the user to: run the project's test suite to confirm no breakage, check for any '# TODO: provide' markers inserted at call sites that need required parameters filled in, and review any modified __init__.py re-exports if symbols were moved." }]
    }
  ]
}
EOF

echo ""
echo "Done. Open this directory in Claude Code — both MCP servers should connect automatically."
echo "Run scripts/test.sh to verify everything works."
echo ""
echo "Enforcement hooks are active: sed/awk on .py/.ts/.tsx files will be blocked and"
echo "redirected to the appropriate bonsai tool."
echo "Run scripts/clean.sh to tear down local dev artifacts."
