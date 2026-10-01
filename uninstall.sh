#!/bin/bash
# uninstall.sh — thin wrapper around `aether uninstall`.
#
# This used to duplicate the CLI's uninstall logic almost line for line, so
# the two drifted: only one of them knew about the gates/ directory. The single
# implementation now lives in bin/aether.
#
# The repo's copy of the CLI is used rather than the installed one, because
# uninstalling deletes ~/.local/bin/aether and bash reads scripts incrementally
# — a script that removes itself mid-run can fail partway through.
#
# Agents are named, never defaulted, exactly as install.sh does: --claude is
# the engine uninstall; --vibe and --codex are owned by
# scripts/install-skills.sh, which removes exactly what it wrote.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  cat <<'EOF'
Usage: bash uninstall.sh <agent...> [scope] [options]

  Agents — at least one required:
  --claude        Remove the Claude Code install: suite hook, gates, CLI
  --vibe          Remove the Vibe Code skills + AGENTS.md block (~/.vibe)
  --codex         Remove the Codex skills + AGENTS.md block (~/.codex)

  Scope and options — the Claude Code uninstall:
  global          Remove the global install (default: this project only)
  --claude-md     Also strip the aether block from CLAUDE.md

The agents compose: bash uninstall.sh --claude --global --claude-md --vibe --codex

The four plugins stay installed for standalone use — remove them with their
own uninstall scripts under plugins/<name>/.
EOF
}

CLAUDE=0
SKILL_AGENTS=()
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --claude) CLAUDE=1 ;;
    --vibe)  SKILL_AGENTS+=(vibe) ;;
    --codex) SKILL_AGENTS+=(codex) ;;
    --global) ARGS+=("global") ;;
    -h|--help) usage; exit 0 ;;
    *) ARGS+=("$arg") ;;
  esac
done

if [ "$CLAUDE" -eq 0 ] && [ "${#SKILL_AGENTS[@]}" -eq 0 ]; then
  printf 'Name what to remove: --claude, --vibe and/or --codex.\n\n' >&2
  usage >&2
  exit 1
fi

if [ "${#SKILL_AGENTS[@]}" -gt 0 ]; then
  bash "$SCRIPT_DIR/scripts/install-skills.sh" uninstall "${SKILL_AGENTS[@]}"
fi

if [ "$CLAUDE" -eq 1 ]; then
  exec bash "$SCRIPT_DIR/bin/aether" uninstall "${ARGS[@]}"
fi

# Engine-scope options without a --claude to apply them to would be silently
# ignored — say so, exactly as install.sh does, rather than let a --global
# look like it removed the global install.
if [ "${#ARGS[@]}" -gt 0 ]; then
  printf 'Note: %s apply to the Claude Code uninstall — add --claude to run it.\n' \
    "${ARGS[*]}" >&2
fi
