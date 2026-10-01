#!/usr/bin/env bash
# tests/test_install_skills.sh — scripts/install-skills.sh, the --vibe/--codex
# install path.
#
# aether's point is install once, work everywhere, and "everywhere" now includes
# agents whose surfaces are a user-level skills directory and a global
# AGENTS.md. Three properties carry all the weight:
#
#   1. The AGENTS.md splice must be idempotent — a re-install that grows the
#      file by a blank line each time is a file the user stops trusting.
#   2. Uninstall must remove exactly what install wrote. The AGENTS.md a user
#      has prose in is the one place "remove everything" would be destructive.
#   3. A stale checkout cannot ship stale skills: install regenerates from the
#      plugin sources rather than copying .agents/skills/.
#
# All three are testable against a throwaway HOME; nothing here touches the
# developer's own ~/.vibe or ~/.codex.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

suite "install-skills"

HOME_FIX=$(mktemp -d)
trap 'rm -rf "$HOME_FIX"' EXIT
run() { HOME="$HOME_FIX" bash "$REPO/scripts/install-skills.sh" "$@"; }

# ── install ──────────────────────────────────────────────────────────────────

run install vibe codex >/dev/null
vibe_n=$(find "$HOME_FIX/.vibe/skills" -name SKILL.md | wc -l | tr -d ' ')
codex_n=$(find "$HOME_FIX/.codex/skills" -name SKILL.md | wc -l | tr -d ' ')
assert_eq "10" "$vibe_n" "vibe: all ten skills land in ~/.vibe/skills"
assert_eq "10" "$codex_n" "codex: all ten skills land in ~/.codex/skills"

vibe_fm=$(cat "$HOME_FIX/.vibe/skills/draft-commit/SKILL.md")
assert_contains "$vibe_fm" "user-invocable: true" "vibe: skills keep their frontmatter"

for agent in vibe codex; do
  grep -q '<!-- aether:start -->' "$HOME_FIX/.$agent/AGENTS.md" \
    && pass "$agent: discipline block written to AGENTS.md" \
    || fail "$agent: discipline block written to AGENTS.md"
done

# ── idempotent splice ────────────────────────────────────────────────────────
# The engine had this bug in CLAUDE.md and fixed it with the trailing-blank
# strip; the same regression here would go unnoticed for weeks.

lines_before=$(wc -l < "$HOME_FIX/.vibe/AGENTS.md" | tr -d ' ')
run install vibe >/dev/null
lines_after=$(wc -l < "$HOME_FIX/.vibe/AGENTS.md" | tr -d ' ')
assert_eq "$lines_before" "$lines_after" "re-install does not grow AGENTS.md"

blocks=$(grep -c '<!-- aether:start -->' "$HOME_FIX/.vibe/AGENTS.md" | tr -d ' ')
assert_eq "1" "$blocks" "re-install leaves exactly one block"

# ── user prose survives both directions ─────────────────────────────────────

mkdir -p "$HOME_FIX/.codex"
printf 'My own global rules.\n' > "$HOME_FIX/.codex/AGENTS.md"
run install codex >/dev/null
grep -q 'My own global rules.' "$HOME_FIX/.codex/AGENTS.md" \
  && pass "install keeps existing AGENTS.md prose" \
  || fail "install keeps existing AGENTS.md prose"

run uninstall codex >/dev/null
grep -q 'My own global rules.' "$HOME_FIX/.codex/AGENTS.md" \
  && pass "uninstall keeps existing AGENTS.md prose" \
  || fail "uninstall keeps existing AGENTS.md prose"
grep -q 'aether:start' "$HOME_FIX/.codex/AGENTS.md" \
  && fail "uninstall strips the aether block" \
  || pass "uninstall strips the aether block"
[ -d "$HOME_FIX/.codex/skills" ] \
  && fail "uninstall removes the skills directory" \
  || pass "uninstall removes the skills directory"

# ── status ───────────────────────────────────────────────────────────────────

status_out=$(run status 2>&1)
assert_contains "$status_out" "10 skill(s)" "status reports the installed count"
run uninstall vibe >/dev/null
status_out=$(run status vibe 2>&1)
assert_contains "$status_out" "0 skill(s)" "status reports zero after uninstall"

# ── a stale checkout cannot ship stale skills ───────────────────────────────
# .agents/skills/ is gitignored output, so simulate the stale case by poisoning
# one; install must still be clean, because it regenerates from plugins/.
mkdir -p "$REPO/.agents/skills/draft-commit"
printf 'stale hand edit\n' > "$REPO/.agents/skills/draft-commit/SKILL.md"
run install vibe >/dev/null
if grep -q 'stale hand edit' "$HOME_FIX/.vibe/skills/draft-commit/SKILL.md"; then
  fail "install regenerates rather than copying .agents/skills/"
else
  pass "install regenerates rather than copying .agents/skills/"
fi
rm -rf "$REPO/.agents"

summary
