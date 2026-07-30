#!/usr/bin/env bash
# Build bonsai's two MCP servers from source.
#
# Extracted from install.sh so the manifest can declare `build: scripts/build.sh`
# and the engine can invoke it without knowing what bonsai is made of. Run from
# anywhere; paths resolve relative to this script.
#
# Skipped entirely under --published, where the servers come from PyPI and npm.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

echo "==> Building Python package (py/)"
(cd "$PLUGIN_ROOT/py" && uv sync --quiet)
echo "  ✓ bonsai-py dependencies installed"

echo "==> Building TypeScript server (ts/)"
(cd "$PLUGIN_ROOT/ts" && npm install --silent && npm run build --silent)
echo "  ✓ bonsai-ts built"
