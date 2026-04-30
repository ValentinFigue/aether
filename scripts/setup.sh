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

echo ""
echo "Done. Open this directory in Claude Code — both MCP servers should connect automatically."
echo "Run scripts/test.sh to verify everything works."
