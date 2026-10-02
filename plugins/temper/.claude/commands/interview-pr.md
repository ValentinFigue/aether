Conduct an interactive review of a PR — walk the reviewer through it bit-by-bit (temper).

`/critique-pr` reviews a PR in one pass and reports findings. Some PRs are too
complex for that: the control flow is hard to follow and the review collapses into
"5K changes: LGTM". This command is the alternative — an interview. You guide the
reviewer through the PR one area at a time, explain each important decision, ask
their opinion, and draft the change requests you agree on as PR comments with
context — then, at the end, ask which to post. By default, nothing is posted
during the interview.

Parse $ARGUMENTS for flags. Supported flags:

- `--pr=<n>` — review a specific PR (default: the one for the current branch)
- `--post` — post each agreed change request as it is agreed, instead of
  collecting them for the end of the interview
- `--comment` — post agreed change requests as plain PR comments (`gh pr comment`)
  instead of a request-changes review verdict
- `--no-post` — never post and do not ask at the end; drafts stay in chat

---

**Step 1 — Resolve the PR**

```bash
gh pr view ${PR_NUMBER:+$PR_NUMBER} --json number,title,url,state,baseRefName,headRefName,body,additions,deletions,changedFiles
```

If there is no PR for the current branch, say so and stop — this command needs a PR.
If the PR is merged or closed, say so and stop.

**Step 2 — Gather context**

```bash
gh pr diff <n> --name-only     # the files
gh pr diff <n>                 # the diff itself — read it, do not skim it
gh pr view <n> --json commits --jq '.commits[] | .messageHeadline'
```

Read the diff end to end before the first question. You are the guide; a guide who
has not read the map asks bad questions.

Build the walkthrough order from what you read — priority first, noise last:

1. The data model — schema changes, new tables or fields, new persisted state
2. New data flowing — where new values enter, how they travel, where they land
3. APIs of the components — public functions, endpoints, contracts other code relies on
4. The core parts — the logic that makes the PR worth merging
5. Everything else — mechanical changes, renames, vendored files; summarise in one turn

**Step 3 — The interview**

This is the whole command. Everything else is setup.

Pacing rules — these are not suggestions:

- **One area per turn.** Never present two areas in the same message.
- **One question at a time.** End every message with the question you want answered,
  and nothing after it.
- **Never advance without an answer.** Stop and wait. Do not answer for the user,
  do not assume agreement, do not continue because the answer seems obvious.
- **Ask my opinion for every important decision or important piece of code** — not
  just the ones you find suspicious. The reviewer's judgement is the point; a
  walkthrough that only asks about problems is a critique with extra steps.

For each area, in order:

- Explain what this bit of the PR does and how it connects to the previous area.
- Name the decisions that were made here and why someone made them that way.
- Point at the exact code: `path/to/file.py:42` and a short quoted fragment, enough
  that the reviewer can find it without scrolling the diff themselves.
- **Every time something warrants the reviewer's attention, say so** — an odd choice,
  a flaky assumption, an edge case handled by a comment instead of code. Flag it
  even if you think it is probably fine; the reviewer decides, not you.
- Ask the question. Wait.

**Step 4 — Requesting a change**

When the reviewer decides a change is warranted, turn the decision into a PR comment
with context. A comment that says only "this is wrong" is noise; each one carries:

- **Where** — `path/to/file.py:42` (or the nearest stable anchor if the line will move)
- **What** — what the code does today, quoted or paraphrased tightly
- **Why it warrants a change** — the decision from the interview, not your opinion
- **What change is requested** — concrete enough to act on

Show the drafted comment in chat, every time. The reviewer must always be able to
veto the wording — these comments may become a request-changes verdict on someone
else's PR, and they agreed to the substance, not yet to the sentence.

By default the comment stops there: record it in the collected list and continue
the interview. Nothing reaches the PR yet — posting is decided once, at the end
(Step 5). Only with `--post` does each comment go out as it is agreed:

```bash
BODY=$(mktemp)
cat > "$BODY" <<'COMMENT'
<the drafted comment>
COMMENT
gh pr review <n> --request-changes --body-file "$BODY"    # default
gh pr comment <n> --body-file "$BODY"                    # with --comment
rm -f "$BODY"
```

If `gh` is missing or not authenticated, say so, keep the drafts in chat, and
continue the interview rather than failing.

**Step 5 — Close**

When every area has been walked through:

**Ask which comments to post** — unless `--no-post` was passed. List each collected
draft by number with its location and a one-line summary, then ask which to post:
all of them, a selection by number, or none. The full text of every draft was
already shown when it was written; posting is a yes on wording the reviewer has
read. Post each selected draft exactly as it was drafted, using the same command
as Step 4. If nothing was collected, skip the question — an interview that
requested no changes should not end by asking about posting. Record the outcome
in the summary: which drafts were posted (with their PR comment links), which were
dropped, and that nothing else was posted.

Then:

- Summarise the decisions made during the interview, and the posting outcome above.
- Persist the summary to `.aether/out/TEMPER.md` (or `~/.aether/out/TEMPER.md` if the
  project has no `.aether/`), wrapped in the same markers as `/critique-pr`:

```
<!-- aether:review date=<ISO 8601 UTC> scope=pr-<n> blockers=<n> significant=<n> minor=<n> -->
# Review — interview — PR #<n> <title> — <date>

…the summary: areas covered, decisions, comments posted or dropped…
<!-- /aether:review -->
```

The three counts are the reviewer's verdicts from the interview: how many agreed
changes were blocking (🔴), significant (🟡) or minor (🟢). They must match the
summary body.

- Record the review against the range the PR covers:

```bash
aether review record --scope=<base> 2>/dev/null || true   # the PR's base branch, e.g. origin/main
```
