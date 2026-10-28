Resolve every reviewer comment on an open PR — plan first, replies drafted in the PR author's own words (temper).

Parse $ARGUMENTS for flags. Supported flags:

| Flag | Effect |
|------|--------|
| `--pr=<n>` | Target a specific PR (default: the one for the current branch) |
| `--post` | Post the approved drafts; without it nothing leaves the session |
| `--no-fix` | Gather, plan and draft only; do not implement anything |
| `--help` | Print this flag table and stop |

`/critique-pr` reviews what someone is about to merge. This resolves what
reviewers already asked: every comment on the PR, a plan to address each one,
and a drafted reply in the author's voice. The plan comes before any change;
the drafts come before anything is posted.

---

## Configuration

Identical to `/critique-pr`: run `aether config show temper --raw`
(local wins), honour `enabled: false` by stopping immediately, and let flags in
$ARGUMENTS override both.

---

## Step 1 — Resolve the PR

```bash
gh pr view ${PR_NUMBER:+$PR_NUMBER} --json number,title,url,state,headRefName,baseRefName,author
```

If there is no open PR for the current branch, say so and stop. If the PR is
merged or closed, say so and stop.

## Step 2 — Gather every comment

Review threads carry state the REST comments endpoint cannot see, so fetch
threads through GraphQL:

```bash
gh api graphql -f query='
query($owner:String!, $name:String!, $number:Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          comments(first: 100) {
            nodes { databaseId author { login } body path line }
          }
        }
      }
      reviews(first: 100) { nodes { author { login } state body } }
      comments(first: 100) { nodes { author { login } body } }
    }
  }
}' -f owner=<owner> -f name=<repo> -F number=<n>
```

Classify each thread:

- **resolved** (`isResolved: true`) or **outdated** (the diff moved past it) —
  skipped, but named in the report: a skipped thread a reviewer believes was
  addressed is worse than an unaddressed one.
- **actionable** — a request that maps to a change.
- **question** — a reviewer asking something; answering it is the change.
- **discussion** — no code change asked; it gets a drafted reply and nothing
  else.

If `gh api graphql` fails (older gh, restricted token), fall back to
`gh api repos/<owner>/<repo>/pulls/<n>/comments` plus
`gh api repos/<owner>/<repo>/issues/<n>/comments` and say plainly that thread
resolution state is unknown — list every comment and let the plan say which
look already handled.

Comments by the PR author are not feedback; they are context (the author
answering earlier reviews).

## Step 3 — The plan, before any change

For each actionable thread: what changes, in which files, and which commit
slice it belongs to. Group related comments into coherent commits — one logical change per
commit, a conventional message per commit. **Never one "PR feedback" blob** —
a reviewer reading the commit list later must be able to tell which request
produced which commit.

Ambiguity is a question, not a guess. If a request could mean two different
changes, or the right fix is a judgement call, the plan carries it as a
question for the user.

Print the plan — threads → changes → commit slices → questions — and stop for
approval. Do not implement anything before the user approves it. If a slice
is non-trivial, the plan gate applies to it like any other change
(`/critique-pr` runs the plan critics).

## Step 4 — Resolve

Implement the approved plan slice by slice. Verify with `aether check` over the
touched files (`2>/dev/null || true` where the CLI may be absent). Commit each
slice with its conventional message, push through the agent's normal push
gates. `--no-fix` skips this step entirely — the drafts then answer the
comments without claiming any change.

## Step 5 — Draft the replies

Every thread gets a reply, drafted in the PR author's voice, shown before
anything is posted.

First the voice: fetch the author's own past comments — on this PR, and on
their two or three most recent PRs in the same repository — and match their
tone, length and formatting. Quote what you matched; the user approves drafts
knowing what the voice reference was.

Then one draft per thread:

- **Addressed** — one or two lines: what changed and where, with the commit
  reference. Not "Done!" — a reply that adds nothing over the commit SHA is
  noise; say what the reviewer could not have known from the diff alone, or
  say nothing beyond the reference.
- **Question answered** — the answer, as short as the question allows.
- **Discussion** — the author's position, in their words.
- **Left open** — why: too large for this PR, belongs elsewhere, disagreed.
  Disagreeing is a valid resolution; a fake agreement is not.

No filler, no praise openers, no "Great catch!", no AI phrasing. Show each
draft beside the comment it answers. When the threads are many, add one
summary comment mapping each thread to its commit; when they are few, skip it
— a summary of two replies is ceremony.

The user edits; the edits replace the drafts verbatim. Nothing is posted
until they approve.

## Step 6 — Post (`--post` only)

Post exactly the approved drafts, nothing more:

- Thread replies: `gh api repos/<owner>/<repo>/pulls/<n>/comments/<id>/replies
  -f body=<file>` — the REST reply endpoint keeps each answer in its thread.
- The summary comment, if one was drafted: `gh pr comment <n> --body-file=<file>`.

Write each draft to a file, post it, and name what was posted. A failed reply
does not stop the rest: post what you can, then report which threads still
need their replies and hand over the exact commands.

Without `--post`, print the drafts and hand over the exact commands to post
them, per the machine's hand-over rules.

## Persist output

Append to `.aether/out/TEMPER.md` (or `~/.aether/out/TEMPER.md` if the project
has no `.aether/`), with the header:

`# Addressed — PR #<n> <title> — <current date>`

Wrap the report in a marker, so it can be read back individually:

```
<!-- aether:addressed date=<ISO 8601 UTC> scope=pr-<n> addressed=<n> open=<n> questions=<n> -->
# Addressed — PR #<n> <title> — <date>

…the plan as approved, what each thread received, what was left open and why…
<!-- /aether:addressed -->
```

Appending, never overwriting. Do **not** run `aether review record`: resolving
feedback is not reviewing the diff — recording it here would tell
`aether review status` this head was reviewed when nobody reviewed the new
commits.
