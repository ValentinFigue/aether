#!/bin/bash
# uninstall.sh — thin wrapper around `aether uninstall`.
#
# This used to duplicate the CLI's uninstall logic almost line for line, so the
# two drifted: only one of them knew about the gates/ directory. The single
# implementation now lives in bin/aether.
#
# The repo's copy of the CLI is used rather than the installed one, because
# uninstalling deletes ~/.local/bin/aether and bash reads scripts incrementally
# — a script that removes itself mid-run can fail partway through.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The CLI spells the scope `global`; accept `--global` too, as install.sh does.
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --global) ARGS+=("global") ;;
    -h|--help)
      cat <<'EOF'
Usage: bash uninstall.sh [global|--global] [--claude-md]

  global        Remove the global install (default: this project only)
  --claude-md   Also strip the aether block from CLAUDE.md

Removes the suite hook, its gates and the aether CLI. The four plugins stay
installed for standalone use — remove them with their own uninstall scripts
under plugins/<name>/.
EOF
      exit 0
      ;;
    *) ARGS+=("$arg") ;;
  esac
done

exec bash "$SCRIPT_DIR/bin/aether" uninstall "${ARGS[@]}"
