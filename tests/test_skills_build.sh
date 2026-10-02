#!/usr/bin/env bash
# tests/test_skills_build.sh — scripts/build-skills.sh, the portable-skill
# generator.
#
# The committed truth is plugins/; .agents/skills/ is gitignored output, the
# same as .claude/commands/. So there is no drift to check against — what needs
# guarding is the generator's contract: given the plugin sources, it must
# produce eleven skills with portable frontmatter, no Claude-specific placeholders,
# and the three targeted patches that keep the skills honest on a machine
# where aether was never installed.
#
# Each assertion has a negative case in the source itself: the un-ported text
# is what the pattern would match if a step were removed.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

suite "skills build"

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
AETHER_SKILLS_OUT="$OUT/skills" bash "$REPO/scripts/build-skills.sh" >/dev/null

# ── Inventory ────────────────────────────────────────────────────────────────

count=$(find "$OUT/skills" -name SKILL.md | wc -l | tr -d ' ')
assert_eq "11" "$count" "all eleven skills are generated"

missing=""
for f in "$OUT"/skills/*/SKILL.md; do
  grep -q '^name:' "$f" || missing="$missing $(basename "$(dirname "$f")"):no-name"
  grep -q '^description:' "$f" || missing="$missing $(basename "$(dirname "$f")"):no-description"
done
assert_eq "" "$missing" "every skill carries name and description frontmatter"

# name: must equal the directory — a skill that violates this is invisible to
# agents routing on the Agent Skills spec.
mismatched=""
for f in "$OUT"/skills/*/SKILL.md; do
  d=$(basename "$(dirname "$f")")
  grep -q "^name: $d\$" "$f" || mismatched="$mismatched $d"
done
assert_eq "" "$mismatched" "skill name matches its directory"

# ── The port steps, one assertion each ──────────────────────────────────────

# $ARGUMENTS is Claude Code substitution; other agents would pass it through
# literally and the skill would parse nothing.
residue=$(grep -rl '\$ARGUMENTS' "$OUT/skills" || true)
assert_eq "" "$residue" "no \$ARGUMENTS placeholders survive the port"

# The user-invocable skills are the ones that surface as slash commands in the
# Vibe Code and Codex pickers; a frontmatter regression makes them
# model-selected only.
invocable=""
for s in draft-commit draft-pr draft-changelog draft-summary \
         critique-diff critique-pr critique-plan interview-pr draft-config; do
  grep -q '^user-invocable: true' "$OUT/skills/$s/SKILL.md" \
    || invocable="$invocable $s"
done
assert_eq "" "$invocable" "all nine commands stay user-invocable"

# On Claude Code the hooks make these calls safe to assume; elsewhere the CLI
# may be absent, so the generated text must degrade instead of failing.
diff_skill=$(cat "$OUT/skills/critique-diff/SKILL.md")
assert_contains "$diff_skill" \
  "aether review record --scope=staged 2>/dev/null || true" \
  "critique-diff records tolerate a missing aether CLI"
plan_skill=$(cat "$OUT/skills/critique-plan/SKILL.md")
assert_contains "$plan_skill" \
  "aether plan status 2>/dev/null || true" \
  "critique-plan plan discovery tolerates a missing aether CLI"
assert_contains "$plan_skill" \
  "aether plan path 2>/dev/null || true" \
  "critique-plan plan pointer tolerates a missing aether CLI"

# The critic definitions live in ~/.claude/commands on Claude Code; on any
# other agent that path does not exist, so the sibling skill is checked first.
pr_skill=$(cat "$OUT/skills/critique-pr/SKILL.md")
assert_contains "$pr_skill" \
  "critique-diff/SKILL.md" \
  "critique-pr reads its critic definitions from the sibling skill"

# The two rules are not user-invocable: the model picks them when the
# situation matches, which is the whole difference between a command and a rule.
for rule in sync-docs bonsai-first; do
  if grep -q '^user-invocable:' "$OUT/skills/$rule/SKILL.md"; then
    fail "$rule stays model-selected (no user-invocable flag)"
  else
    pass "$rule stays model-selected (no user-invocable flag)"
  fi
done

summary
