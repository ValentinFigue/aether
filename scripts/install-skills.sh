#!/usr/bin/env bash
# scripts/install-skills.sh — install the portable skills for other agents.
#
# The engine installs into Claude Code's surfaces: settings.json, hooks,
# .claude/commands. Vibe Code and Codex have different ones — user-level skill
# directories and a global AGENTS.md — and rather than teach the manifest
# engine a second agent model, this script owns those destinations:
#
#   vibe:  $VIBE_HOME (default ~/.vibe)    skills/  + AGENTS.md block
#   codex: $CODEX_HOME (default ~/.codex)  skills/  + AGENTS.md block
#
# install.sh --vibe / --codex delegate here, and compose with the Claude Code
# install, which is named like the rest:
#
#   bash install.sh --claude --global --claude-md --vibe --codex
#
# Two properties worth naming:
#
#   - Skills are generated fresh from the plugin sources on every run, never
#     copied from .agents/skills/, so a stale checkout cannot ship stale
#     skills. The same generated list is what uninstall removes — no manifest
#     file to drift out of sync.
#   - The AGENTS.md block uses the same `aether` sentinels as the CLAUDE.md
#     block, so re-install replaces it and uninstall strips exactly what
#     install wrote, leaving any user prose in the file untouched.
#
#   bash scripts/install-skills.sh install [vibe codex]   # default: both
#   bash scripts/install-skills.sh uninstall [vibe codex]
#   bash scripts/install-skills.sh status

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

usage() {
  cat <<'EOF'
Usage: bash scripts/install-skills.sh <command> [agent...]

  install   [vibe codex]   Install skills + AGENTS.md block (default: both)
  uninstall [vibe codex]   Remove exactly what install wrote
  status                   Report what is installed, and where
EOF
}

agent_root() {
  case "$1" in
    vibe)  printf '%s' "${VIBE_HOME:-$HOME/.vibe}" ;;
    codex) printf '%s' "${CODEX_HOME:-$HOME/.codex}" ;;
  esac
}

# ── Build ────────────────────────────────────────────────────────────────────

built=""
build() {
  [ -n "$built" ] && return 0
  built=$(mktemp -d)
  AETHER_SKILLS_OUT="$built" bash "$REPO/scripts/build-skills.sh" >/dev/null
}
cleanup() { [ -n "$built" ] && rm -rf "$built"; }
trap cleanup EXIT

# ── AGENTS.md block ──────────────────────────────────────────────────────────
# Mirrors the engine's _op_splice/_op_unsplice: same sentinels, same one-blank-
# line separation, same trailing-blank-line strip that makes re-install
# idempotent instead of growing the file by a line each time.

splice_agents_md() { # <file>
  local file="$1" marker=aether
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || : > "$file"
  [ -s "$file" ] && cp "$file" "$file.bak"
  if grep -q "<!-- ${marker}:start -->" "$file" 2>/dev/null; then
    awk "/<!-- ${marker}:start -->/{skip=1} !skip{print} /<!-- ${marker}:end -->/{skip=0}" \
      "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi
  awk '{ l[NR] = $0 }
       END { last = NR
             while (last > 0 && l[last] ~ /^[[:space:]]*$/) last--
             for (i = 1; i <= last; i++) print l[i] }' \
    "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  {
    [ -s "$file" ] && printf '\n'
    printf '<!-- %s:start -->\n' "$marker"
    cat "$REPO/AGENTS.md"
    printf '<!-- %s:end -->\n' "$marker"
  } >> "$file"
}

unsplice_agents_md() { # <file>
  local file="$1" marker=aether
  [ -f "$file" ] || return 0
  [ -s "$file" ] && cp "$file" "$file.bak"
  awk "/<!-- ${marker}:start -->/{skip=1} !skip{print} /<!-- ${marker}:end -->/{skip=0}" \
    "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# ── Per-agent ────────────────────────────────────────────────────────────────

install_for() {
  local agent="$1" root skills d name count=0
  root=$(agent_root "$agent")
  skills="$root/skills"
  build
  mkdir -p "$skills"
  for d in "$built"/*/; do
    d="${d%/}"; name=$(basename "$d")
    rm -rf "$skills/$name"
    cp -R "$d" "$skills/$name"
    count=$((count + 1))
  done
  splice_agents_md "$root/AGENTS.md"
  printf '  %s %s: %s skills -> %s, discipline block -> %s\n' \
    '✓' "$agent" "$count" "$skills" "$root/AGENTS.md"
}

uninstall_for() {
  local agent="$1" root skills d name removed=0
  root=$(agent_root "$agent")
  skills="$root/skills"
  build
  for d in "$built"/*/; do
    d="${d%/}"; name=$(basename "$d")
    if [ -d "$skills/$name" ]; then
      rm -rf "$skills/$name"
      removed=$((removed + 1))
    fi
  done
  unsplice_agents_md "$root/AGENTS.md"
  rmdir "$skills" 2>/dev/null || true
  printf '  %s %s: removed %s skills and the AGENTS.md block\n' '✓' "$agent" "$removed"
}

status_for() {
  local agent="$1" root n block
  root=$(agent_root "$agent")
  if [ -d "$root/skills" ]; then
    n=$(find "$root/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  else
    n=0
  fi
  if [ -f "$root/AGENTS.md" ] && grep -q '<!-- aether:start -->' "$root/AGENTS.md" 2>/dev/null; then
    block="present"
  else
    block="absent"
  fi
  printf '  %s: %s skill(s), AGENTS.md block %s (%s)\n' "$agent" "$n" "$block" "$root"
}

# ── Dispatch ────────────────────────────────────────────────────────────────

valid_agents() {
  local a
  for a in "$@"; do
    case "$a" in
      vibe|codex) ;;
      *) printf 'Unknown agent: %s (expected vibe or codex)\n' "$a" >&2; usage; exit 1 ;;
    esac
  done
}

cmd="${1:-}"; shift || true
agents=("$@")
[ ${#agents[@]} -eq 0 ] && agents=(vibe codex)

case "$cmd" in
  install|uninstall)
    valid_agents "${agents[@]}"
    for a in "${agents[@]}"; do "${cmd}_for" "$a"; done
    ;;
  status)
    valid_agents "${agents[@]}"
    for a in "${agents[@]}"; do status_for "$a"; done
    ;;
  *)
    usage
    exit 1
    ;;
esac
