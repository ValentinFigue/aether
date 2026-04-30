#!/usr/bin/env bash
set -e

echo "==> Removing local dev hook config (.claude/settings.json)"
rm -f .claude/settings.json

echo "==> Removing Python virtual environment"
rm -rf py/.venv

echo "==> Removing TypeScript build output"
rm -rf ts/dist ts/node_modules

echo ""
echo "Done. Run scripts/setup.sh to set up again."
echo "To remove globally-registered MCP servers:"
echo "  claude mcp remove bonsai-py --scope user"
echo "  claude mcp remove bonsai-ts --scope user"
