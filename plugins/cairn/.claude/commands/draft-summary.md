Draft a standup, Slack or prose summary of recent commits (cairn).

Parse $ARGUMENTS for flags. Supported flags:
- `--from=<ref>` — starting ref or time expression; default: `1 day ago`
- `--to=<ref>` — ending ref; default: `HEAD`
- `--format=standup` (default) — bullet list with Yesterday/Today structure
- `--format=slack` — 2–4 sentence conversational paragraph
- `--format=paragraph` — formal prose for PR descriptions or weekly reports
- `--author=<email|name>` — filter to commits by a specific author

---

**Step 1 — Read config**

Run:

```bash
aether config show cairn --raw 2>/dev/null || true
```

Each line is `key: value`, already resolved — global `~/.aether/config`, then the
project's `.aether/config`, per key, with declared defaults filled in. Nothing
left to merge. If it prints nothing (aether missing or pre-1.1), use the
documented fallbacks below and continue rather than failing.

Resolve:
- `summary.format` — default format if `--format` not in $ARGUMENTS; fallback to `standup`
- `summary.window` — default time window if `--from` not in $ARGUMENTS; fallback to `1 day ago`

**Step 2 — Read commits**

If `--from` is provided and looks like a git ref (tag, SHA, branch name — not a time expression), use ref-based range:

```bash
git log --pretty=format:"%an|%s%n%b%n---END---" [--author=<author>] <from>..<to>
git diff --stat <from>..<to>
```

Otherwise use time-based range (default or when `--from` looks like a time expression like `"1 day ago"`, `"1 week ago"`):

```bash
git log --since="<window>" --pretty=format:"%an|%s%n%b%n---END---" [--author=<author>]
git diff --stat --since="<window>"
```

**Empty-log handling:** if no commits are returned, print:

`No commits found in the specified range. Pass \`--from=<ref>\` to specify a different range.`

and stop.

**Step 3 — Generate summary**

Resolve format:
1. `--format=<x>` in $ARGUMENTS
2. `summary.format` from config
3. Default: `standup`

**Format: `standup`** — bullet list, 3–6 bullets, past tense, grouped as Yesterday/Today:

```
Yesterday:
- <bullet describing a logical change — past tense, plain language, no jargon>
- <bullet>
- <bullet>

Today:
- (fill in your plans)
```

Rules: each bullet is one sentence, describes a meaningful change, avoids technical details that don't communicate intent to a non-technical reader. If commits span more than one day, label sections by date instead of Yesterday/Today.

**Format: `slack`** — 2–4 sentences, conversational, no bullet structure:

```
<2–4 sentence paragraph summarising what was shipped and why it matters, as you'd write in a Slack message>
```

**Format: `paragraph`** — formal prose, 1–3 paragraphs, suitable for a PR description body or weekly engineering report:

```
<Paragraph 1 — overall summary of the work and motivation>

<Paragraph 2 — key changes and their impact (optional, if enough content)>

<Paragraph 3 — anything notable: breaking changes, decisions made, open questions (optional)>
```

Rules for all formats:
- Focus on WHY changes were made, not just what files changed
- Avoid commit message syntax — write natural language
- If `--author` was used, frame the summary around that person's contributions
- Do not invent details not present in the commits

**Step 4 — Output**

Print the summary in a fenced block. Do not write any files. Do not run `git commit`.
