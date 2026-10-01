#!/usr/bin/env bash
# scripts/build-skills.sh — regenerate .agents/skills/ from the plugin sources.
#
# .agents/skills/ is generated output, not a second copy to maintain: each
# skill body lives once, under plugins/, and this script is its only writer —
# the same model the installer already uses ("generated from files that are
# already versioned under plugins/"), extended to the portable Agent Skills
# format (https://agentskills.io) that Vibe Code and Codex read. Like
# .claude/commands/, it is gitignored: the committed truth is plugins/, and
# scripts/install-skills.sh rebuilds on every install so a stale checkout
# cannot ship stale skills.
#
# What it does to each command file:
#   - prepends frontmatter (name, description, user-invocable, argument-hint)
#   - $ARGUMENTS       → "the invocation arguments"
#   - "the Bash tool"  → "the shell"
#   - aether CLI calls that would be fatal on a machine without aether →
#     tolerant (2>/dev/null || true), so the skill degrades to its documented
#     defaults rather than failing
#   - critique-pr reads its critic definitions from the sibling skill rather
#     than ~/.claude/commands
#
#   bash scripts/build-skills.sh   # write the portable skills (default:
#                                   .agents/skills/, gitignored; AETHER_SKILLS_OUT
#                                   overrides — install-skills.sh builds to a
#                                   throwaway directory)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OUT="${AETHER_SKILLS_OUT:-$REPO/.agents/skills}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SK="$TMP/skills"

# The generic port: command file prose → agent-neutral prose.
GENERIC='
  s/\$ARGUMENTS/the invocation arguments/g;
  s/using the Bash tool/using the shell/g;
  s/Run these Bash commands/Run these shell commands/g;
  s/the Bash tool/the shell/g;
'

# Per-skill patches, layered on the generic port. Apostrophe-free by
# construction: they ride in single-quoted perl programs below.
PATCH_DIFF_RECORD='
  s/(aether review record --scope=staged)\s+#/$1 2>\/dev\/null || true  #/;
  s/# or --scope=all, or the ref you reviewed\n/# or --scope=all, or the ref you reviewed; skip if the aether CLI is not installed\n/;
  s/Skip it only if you reviewed nothing\./Skip it if you reviewed nothing or the aether CLI is not installed./;
'
PATCH_PR='
  s/- `~\/\.claude\/commands\/critique-diff\.md` \(global install\)\n- `\.claude\/commands\/critique-diff\.md` \(local install\)/- `critique-diff\/SKILL.md` next to this skill (`.agents\/skills\/critique-diff\/SKILL.md` in the aether repo)\n- `~\/.claude\/commands\/critique-diff.md` (global Claude Code install)\n- `.claude\/commands\/critique-diff.md` (local Claude Code install)/;
  s/(aether review record --scope=<base>)\s+#/$1 2>\/dev\/null || true  #/;
  s/(# the PR.s base branch, e\.g\. origin\.main)\n/$1; skip if the aether CLI is not installed\n/;
'
PATCH_PLAN='
  s/```bash\naether plan status\n```/```bash\naether plan status 2>\/dev\/null || true\n```/;
'

# command_skill <name> <src> [patch...] — frontmatter + ported body.
command_skill() {
  local name="$1" src="$2"; shift 2
  local d="$SK/$name"
  mkdir -p "$d"
  "fm_${name//-/_}" > "$d/SKILL.md"
  perl -0pe "$GENERIC" "$src" > "$TMP/body"
  local p
  for p in "$@"; do perl -0pi -e "$p" "$TMP/body"; done
  cat "$TMP/body" >> "$d/SKILL.md"
}

# ── Frontmatter ─────────────────────────────────────────────────────────────
# Description carries the routing: agents that follow the Agent Skills spec
# load a skill's body only after its description matches the situation.

fm_draft_commit() { cat <<'EOF'
---
name: draft-commit
description: >
  Draft a commit message from the staged diff (cairn). Use when the user asks
  to write, suggest, or improve a commit message, or before committing staged
  changes. Reads aether config for style, scans the diff for secrets, and
  prints the message without committing.
user-invocable: true
argument-hint: "[--style=conventional|plain] [--off]"
---

EOF
}

fm_draft_pr() { cat <<'EOF'
---
name: draft-pr
description: >
  Draft a PR title and description from the branch diff (cairn). Use when the
  user asks to write a PR description or is about to open a pull request.
  Honours .aether templates and rules, scans for secrets, and with --apply
  pushes the description to the PR via gh.
user-invocable: true
argument-hint: "[--base=<branch>] [--style=conventional|plain] [--apply] [--title] [--pr=<n>]"
---

EOF
}

fm_draft_changelog() { cat <<'EOF'
---
name: draft-changelog
description: >
  Draft a CHANGELOG entry from a commit range (cairn). Use when the user asks
  for release notes or a changelog entry. Groups commits into Keep-a-Changelog
  sections from conventional subjects and prints the entry ready to paste;
  writes nothing.
user-invocable: true
argument-hint: "[--from=<ref>] [--to=<ref>] [--version=<semver>] [--style=conventional|plain]"
---

EOF
}

fm_draft_summary() { cat <<'EOF'
---
name: draft-summary
description: >
  Draft a standup, Slack, or prose summary of recent commits (cairn). Use when
  the user asks for a status update, standup notes, or a summary of recent
  work. Formats: standup bullets, a conversational Slack paragraph, or formal
  prose for reports.
user-invocable: true
argument-hint: "[--from=<ref>] [--format=standup|slack|paragraph] [--author=<email>]"
---

EOF
}

fm_critique_diff() { cat <<'EOF'
---
name: critique-diff
description: >
  Critique a diff before commit or push (temper). Five severity-rated critics
  — correctness, design, risk, coverage, documentation — plus a secrets scan
  and an optional measurement pass via aether check. Use when the user asks to
  review, critique, or sanity-check a diff, staged changes, or the last commit.
user-invocable: true
argument-hint: "[--only=<critics>] [--skip=<critics>] [--severity=red,yellow] [--diff=staged|unstaged|all|<ref>] [--target=<file>]"
---

EOF
}

fm_critique_pr() { cat <<'EOF'
---
name: critique-pr
description: >
  Critique an open PR before merge (temper). Temper's five critics plus a
  description-accuracy critic that checks the PR body against the diff, with
  CI state and an optional aether check measurement pass. Use when the user
  asks to review a pull request before merging.
user-invocable: true
argument-hint: "[--pr=<n>] [--only=<critics>] [--skip=<critics>] [--severity=red,yellow]"
---

EOF
}

fm_critique_plan() { cat <<'EOF'
---
name: critique-plan
description: >
  Critique an implementation plan before coding starts (whetstone). Runs
  implementation, architecture, and risk critics — optionally testing,
  complexity, API contract, and cost/ops — to surface blockers while they are
  still cheap. Use when the user asks to review or critique a plan before
  implementing it.
user-invocable: true
argument-hint: "[--only=<critics>] [--skip=<critics>] [--severity=red,yellow]"
---

EOF
}

fm_draft_config() { cat <<'EOF'
---
name: draft-config
description: >
  Survey the repository and write the aether config it implies (trellis).
  Detects test, lint, typecheck and build commands from CI and manifests, git
  conventions, and per-plugin defaults, then writes them with aether config set
  and asks about the gaps. Use when the user asks to set up or bootstrap aether
  for a project.
user-invocable: true
argument-hint: "[--global] [--dry-run] [--only=<sections>] [--force]"
---

EOF
}

fm_bonsai_first() { cat <<'EOF'
---
name: bonsai-first
description: >
  Redirects structural code operations on Python and TypeScript files to the
  correct bonsai AST tool. Use before reaching for sed, grep, awk, or find on
  .py/.ts/.tsx files. Covers renaming, moving, finding references, signature
  changes, and dead-code detection. Requires the bonsai MCP servers
  (bonsai-py, bonsai-ts); if they are not configured, say so and fall back to
  text tools.
---

EOF
}

# ── Build ────────────────────────────────────────────────────────────────────

cd "$REPO"

command_skill draft-commit    plugins/cairn/.claude/commands/draft-commit.md
command_skill draft-pr       plugins/cairn/.claude/commands/draft-pr.md
command_skill draft-changelog plugins/cairn/.claude/commands/draft-changelog.md
command_skill draft-summary  plugins/cairn/.claude/commands/draft-summary.md
command_skill critique-diff  plugins/temper/.claude/commands/critique-diff.md "$PATCH_DIFF_RECORD"
command_skill critique-pr    plugins/temper/.claude/commands/critique-pr.md "$PATCH_PR"
command_skill critique-plan  plugins/whetstone/.claude/commands/critique-plan.md "$PATCH_PLAN"
command_skill draft-config   plugins/trellis/.claude/commands/draft-config.md

# sync-docs already ships as a portable skill — body and frontmatter are one
# file, so the generated copy is a plain copy.
mkdir -p "$SK/sync-docs"
cp plugins/temper/skills/sync-docs/SKILL.md "$SK/sync-docs/SKILL.md"

# bonsai-first: body shared with the Claude skill; only the frontmatter differs
# (the Claude one pins allowed-tools to the bonsai MCP tools, which do not
# exist on a machine without the servers). Body from the shared heading down.
mkdir -p "$SK/bonsai-first"
fm_bonsai_first > "$SK/bonsai-first/SKILL.md"
awk '/^# Bonsai-first/{on=1} on' plugins/bonsai/skills/bonsai-first/SKILL.md \
  >> "$SK/bonsai-first/SKILL.md"

# ── Emit ─────────────────────────────────────────────────────────────────────

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
cp -R "$SK" "$OUT"
count=$(find "$OUT" -name SKILL.md | wc -l | tr -d ' ')
printf 'Generated %s skills in %s\n' "$count" "$OUT"
