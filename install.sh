#!/bin/bash
# install.sh — thin entry point over the aether engine.
#
# The engine lives in bin/aether and is driven by plugins/<name>/aether.plugin.
# This script used to be 530 lines of imperative install steps, duplicated in
# four more per-plugin installers; all five expressed the same five operations
# over data that is now declared in the manifests.
#
# Runs bin/aether straight out of the clone, before anything is installed.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

case " $* " in *" -h "*|*" --help "*)
  cat <<'USAGE'
aether — install the whetstone → bonsai → temper → cairn suite

  bash install.sh [global|--global] [--claude-md] [--no-bonsai] [plugin...]

  --global       Install for every project (default: this project only)
  --claude-md    Write the unified rules block into CLAUDE.md
  --no-bonsai    Skip bonsai, the only plugin needing uv, node and npm
  plugin...      Install only the named plugins

Everything is installed from this clone; no network access is used. Keep the
clone: bonsai registers its MCP servers by absolute path into it.
USAGE
  exit 0 ;;
esac

exec bash "$SCRIPT_DIR/bin/aether" install "$@"
