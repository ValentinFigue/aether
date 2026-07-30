Critique an open PR before merge — temper's four critics plus description accuracy (temper).

Parse $ARGUMENTS for flags. Supported flags:

| Flag | Effect |
|------|--------|
| `--pr=<n>` | Review a specific PR (default: the one for the current branch) |
| `--only=correctness,risk` | Run only these critics |
| `--skip=coverage` | Run all defaults except the named one(s) |
| `--severity=red` | Report only 🔴 findings |
| `--severity=red,yellow` | Report 🔴 and 🟡 findings |
| `--off` | Print "temper disabled for this run." and stop |
| `--help` | Print this flag table and stop |

`/critique-diff` reviews what you are about to commit. This reviews what someone is
about to merge: the whole PR, its metadata, and whether its description still tells the
truth about the diff.

---

## Configuration

Identical to `/critique-diff`: run `aether config show temper --raw`
(local wins), honour `enabled: false` by stopping immediately, and let flags in
$ARGUMENTS override both.

---

## Step 1 — Resolve the PR

```bash
gh pr view ${PR_NUMBER:+$PR_NUMBER} --json number,title,url,state,baseRefName,headRefName,body,isDraft,mergeable,mergeStateStatus
```

If there is no PR for the current branch, print:

```
No open PR for this branch. /critique-diff reviews uncommitted work;
/critique-pr needs a PR to review.
```

and stop. If the PR is already merged or closed, say so and stop.

## Step 2 — Gather context

Cheap to collect and it answers the boring blockers before any critic runs:

```bash
gh pr checks <n>                                    # CI state
gh pr diff <n>                                      # the review surface
gh pr view <n> --json commits --jq '.commits|length'
git rev-list --count <head>..<base>                 # commits behind base
```

Note whether any test files appear in the diff, the total files and lines changed, and
the primary languages.

**`gh pr checks` is not a substitute for running anything.** It reports what CI
chose to run on some commit, which may not be the head, and a repo with no
workflows reports nothing at all — an empty check list is not a passing one. Say
which it is.

If the branch is checked out locally, run the measurement pass from
`/critique-diff`: `aether check $(gh pr diff <n> --name-only) --raw`, plus
`aether rules`. `aether check` is the only thing that executes `[project]` commands —
it resolves each changed file to its monorepo area and runs that area's commands in
its own directory. `build` matters most here: it is the difference between "the
description says it compiles" and knowing.

Name every area you checked **and every area you skipped**. If the branch is not
checked out, say that instead of implying the checks were yours.

Report this as a short context block above the findings table — it is context, not
findings:

```
PR #<n> — <title>
  <base> ← <head>   <n> commits, +<a>/−<b> across <f> files
  checks:    <p>/<t> passing        mergeable: <state>
  tests:     <n> test files touched (or: none)
  behind base: <n> commits
```

Add a line for anything you ran yourself, kept separate from CI's result:

```
  ran here: project:backend  test ✓  build ✗ (npm run build)
            project:web      lint ✓  typecheck ✓
            project:canvas_processor  not touched — skipped
```

If checks are failing or the PR is not mergeable, say so plainly here. A red CI is
worth knowing before reading a review of the code. If `[project]` is unset or the
project is untrusted, say that once — the reader should know the review is a
reading of the diff and nothing more.

## Step 3 — Secrets scan

Same as `/critique-diff`, over the full PR diff: `sk-`, `AKIA`, `ghp_`, `ghs_`,
`-----BEGIN`, high-entropy strings near `key`/`secret`/`token`/`password`/`credential`,
and any `.env*` file added.

Report matches in a warning block above the table and continue. This is the one class
of finding that cannot be undone after a merge is pushed — history rewrite plus
credential rotation — so it is scanned first and never suppressed by `--severity`.

## Step 4 — Critics 1–4

**Do not restate temper's critic definitions here.** They live in `critique-diff.md`,
which installs into the same directory as this file, and duplicating them is how the
two drift apart.

Read it and apply its **Critic 1 — Correctness**, **Critic 2 — Design**,
**Critic 3 — Risk** and **Critic 4 — Coverage** sections to the PR diff, honouring
`--only` / `--skip`:

- `~/.claude/commands/critique-diff.md` (global install)
- `.claude/commands/critique-diff.md` (local install)

If neither is readable, fall back to these summaries and note in the output that the
full definitions were unavailable:

- **Correctness** — logic errors, wrong conditionals, off-by-one, null dereferences,
  unhandled error paths, wrong assumptions about input, races and shared state.
- **Design** — unnecessary coupling, leaky abstractions, misleading names, duplication
  that belongs in a shared utility, premature complexity, overloaded functions.
- **Risk** — injection, auth bypass, insecure defaults, trust-boundary violations, data
  loss, breaking changes to public contracts, missing observability on new failure paths.
- **Coverage** — new code paths without tests, existing tests invalidated by the change,
  untested edge cases, changes that make code harder to test.

## Step 5 — Critic 5 — Description accuracy

The critic that only exists here, because only a PR has a description.

Re-read the PR body against the diff you actually gathered and flag:

- **Claims that are no longer true** — the description says something the code no longer
  does, usually because the branch moved on after the body was written.
- **Work described but not present** — a section covering something that got dropped,
  deferred or split out.
- **Significant changes never mentioned** — the reverse, and the more dangerous one. A
  reviewer who trusts the description will not look for what it does not name. Weight
  this by blast radius: an unmentioned refactor of an install path matters more than an
  unmentioned typo fix.
- **A test plan that does not match the tests** — steps referencing files or commands
  that are not in the diff.

Rate on the same scale. A description that actively misleads a reviewer about a risky
change is 🔴; an omission of something minor is 🟢.

## Report

Same format as `/critique-diff` — the context block from Step 2, then:

| # | Critic | Severity | Finding | Recommendation |
|---|--------|----------|---------|----------------|

Followed by **Blockers / Significant / Minor** counts.

If nothing is found: "Nothing to flag — good to merge."

## Gate

- Any 🔴: **Blocked.** Resolve them, or merge deliberately with a written reason.
- Only 🟡/🟢: one-line summary, e.g. _"4 findings (0 🔴, 2 🟡, 2 🟢). Good to merge with
  the above addressed."_

Unlike `/critique-diff` there is no `# temper:skip` equivalent — this command is invoked
by hand, so choosing to merge anyway is already an explicit act.

## Persist output

Append to `.aether/out/TEMPER.md` (or `~/.aether/out/TEMPER.md` if the project
has no `.aether/`), with the header:

`# Review — PR #<n> <title> — <current date>`

Appending, never overwriting, so the file accumulates a history across reviews.
