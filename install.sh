#!/bin/bash
# install.sh — thin entry point over the aether engine.
#
# The engine lives in bin/aether and is driven by plugins/<name>/aether.plugin.
# This script used to be 530 lines of imperative install steps, duplicated in
# four more per-plugin installers; all five expressed the same five operations
# over data that is now declared in the manifests.
#
# Runs bin/aether straight out of the clone, before anything is installed.
#
# Agents are named, never defaulted: at least one of --claude / --vibe /
# --codex is required, so no agent is silently the assumed one. --claude is
# the engine install (hooks, gates, slash commands); --vibe and --codex are
# owned by scripts/install-skills.sh, and the engine never sees those
# arguments.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  cat <<'USAGE'
aether — install the whetstone → bonsai → temper → cairn suite

  bash install.sh <agent...> [scope] [options]

  Agents — at least one required:
  --claude        Claude Code: hooks, gates, slash commands
  --vibe          Vibe Code: portable skills + AGENTS.md block (~/.vibe)
  --codex         Codex: portable skills + AGENTS.md block (~/.codex)

  Scope and options — the Claude Code install:
  --global        Install for every project (default: this project only)
  --claude-md     Write the unified rules block into CLAUDE.md
  --no-bonsai     Skip bonsai, the only plugin needing uv, node and npm
  --dry-run       Print every step, change nothing
  plugin...       Install only the named plugins

The agents compose:
  bash install.sh --claude --global --claude-md --vibe --codex

Everything is installed from this clone; no network access is used. Keep the
clone: bonsai registers its MCP servers by absolute path into it.
USAGE
}

case " $* " in *" -h "*|*" --help "*) usage; exit 0 ;; esac

# Split the agent targets from the engine's own arguments.
CLAUDE=0
SKILL_AGENTS=()
ENGINE_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --claude) CLAUDE=1 ;;
    --vibe)  SKILL_AGENTS+=(vibe) ;;
    --codex) SKILL_AGENTS+=(codex) ;;
    *)       ENGINE_ARGS+=("$arg") ;;
  esac
done

# No agent named: refuse rather than silently install one. The refusal is the
# feature — "which agents?" is a question worth answering out loud.
if [ "$CLAUDE" -eq 0 ] && [ "${#SKILL_AGENTS[@]}" -eq 0 ]; then
  printf 'Pick at least one agent: --claude, --vibe or --codex.\n\n' >&2
  usage >&2
  exit 1
fi

if [ "${#SKILL_AGENTS[@]}" -gt 0 ]; then
  bash "$SCRIPT_DIR/scripts/install-skills.sh" install "${SKILL_AGENTS[@]}"
fi

if [ "$CLAUDE" -eq 1 ]; then
  exec bash "$SCRIPT_DIR/bin/aether" install "${ENGINE_ARGS[@]}"
fi

# Engine-only options without a --claude to apply them to would be silently
# ignored — say so, rather than let a --global look like it did something.
if [ "${#ENGINE_ARGS[@]}" -gt 0 ]; then
  printf 'Note: %s apply to the Claude Code install — add --claude to run it.\n' \
    "${ENGINE_ARGS[*]}" >&2
fi
