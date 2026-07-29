Draft a PR title and description from the branch diff (cairn).

Parse $ARGUMENTS for flags. Supported flags:
- `--base=<branch>` — base branch to diff against (default: auto-detected)
- `--style=conventional` (default) — Conventional Commits PR title format
- `--style=plain` — plain imperative PR title, no type prefix

---

**Step 1 — Read config**

Run this single Bash command:

```bash
{ cat ./cairn.config 2>/dev/null; echo "---CAIRN_SEP---"; cat "$HOME/.claude/cairn.config" 2>/dev/null; }
```

Split on `---CAIRN_SEP---`. Local config (before) takes precedence over global (after).

Resolve settings:
- `pr.base` — default base branch if `--base` not in $ARGUMENTS
- `pr.style` — default style if `--style` not in $ARGUMENTS; fallback to `style:` key; fallback to `conventional`
- `pr.template_file` — path to PR description template file (optional)
- `pr.rules_file` — path to prose generation rules file (optional)

**Step 2 — Detect base branch**

If `--base=<branch>` is in $ARGUMENTS, use that. Otherwise use `pr.base` from config. Otherwise auto-detect:

```bash
git rev-parse --verify origin/main >/dev/null 2>&1 && echo "main" || \
git rev-parse --verify origin/master >/dev/null 2>&1 && echo "master" || \
git rev-parse --verify main >/dev/null 2>&1 && echo "main" || \
echo "master"
```

Store the result as `<base>`.

**Step 3 — Read diff and context**

Run these Bash commands:

```bash
# Find the divergence point
MERGE_BASE=$(git merge-base HEAD <base> 2>/dev/null || git merge-base HEAD origin/<base> 2>/dev/null || echo "")

# Full diff
git diff ${MERGE_BASE}..<base_or_head> 2>/dev/null || git diff HEAD~1..HEAD

# Commit list
git log --oneline ${MERGE_BASE}..HEAD 2>/dev/null

# Changed files
git diff --name-only ${MERGE_BASE}..HEAD 2>/dev/null

# Current branch name (for ticket number extraction)
git rev-parse --abbrev-ref HEAD
```

If the diff is empty, print: "No commits ahead of `<base>`. Nothing to describe." and stop.

**Step 4 — Secrets check**

Scan the diff for:
- `sk-` (OpenAI / Stripe keys)
- `AKIA` (AWS access key prefix)
- `ghp_` or `ghs_` (GitHub tokens)
- `-----BEGIN` (PEM private keys)
- High-entropy strings (`[a-zA-Z0-9]{32,}`) on `+` lines near words like `key`, `token`, `secret`, `password`, `api_key`

If found, print a warning block and continue (do not stop).

**Step 5 — Read template and rules files (if configured)**

If `pr.template_file` was set in config:
```bash
cat <pr.template_file> 2>/dev/null || echo ""
```
If the file exists, use its structure as the output format (fill in each section).
If the file is missing, print: `⚠️  pr.template_file set but not found: <path>` and use the default format.

If `pr.rules_file` was set in config:
```bash
cat <pr.rules_file> 2>/dev/null || echo ""
```
If the file exists, apply its instructions to the generation.
If the file is missing, print: `⚠️  pr.rules_file set but not found: <path>` and continue without rules.

**Step 6 — Generate PR title and description**

Resolve style:
1. `--style=<x>` in $ARGUMENTS
2. `pr.style` from config
3. `style` from config
4. Default: `conventional`

**PR Title** — same rules as /draft-commit:
- Conventional style: `<type>(<scope>): <short description>` (≤ 72 chars)
- Plain style: short imperative description (≤ 72 chars)
- If the branch name contains a ticket number pattern (e.g. `PROJ-123`, `issue-42`), include it in the title suffix: `feat(auth): add token validation [PROJ-123]`

**PR Description** — if a template file was provided, fill in its sections. Otherwise use this default structure:

```
## Summary

- <bullet 1 — imperative, describes a logical change>
- <bullet 2>
- <bullet 3> (1–4 bullets total)

## Changes

- `<file or module>` — <one-line description of what changed>
(one line per changed file or logical area; omit if fewer than 3 files changed)

## Test plan

- [ ] <test step referencing actual test files found in the diff>
- [ ] <manual test step>
```

Rules:
- Summary bullets: imperative mood, describe WHY as much as WHAT
- Changes section: omit if fewer than 3 files changed
- Test plan: reference actual test files found in the diff by name; add at least one manual verification step
- If the diff is large (>300 lines), summarise by file area rather than line-by-line
- Apply any additional instructions from `pr.rules_file` if loaded in Step 5

**Step 7 — Output**

Print the PR title and description in a single fenced block, ready to paste:

```
PR Title:
<title>

Description:
<description>
```

Do not run any git commands. Do not modify any files.
