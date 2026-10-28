Watch an open PR's CI to its end — triage the failures, then alert, or merge when everything is approved (cairn).

Parse $ARGUMENTS for flags. Supported flags:

| Flag | Effect |
|------|--------|
| `--pr=<n>` | Target a specific PR (default: the one for the current branch) |
| `--interval=<sec>` | Seconds between polls (default: 120) |
| `--timeout=<min>` | Minutes before the watch gives up and alerts (default: 45) |
| `--merge` | Authorize the merge once everything is green and approved |
| `--no-fix` | Report failures and stop; do not attempt fixes |
| `--help` | Print this flag table and stop |

`/draft-pr` writes what a PR says. This watches what a PR does between the
review and the merge: polls CI with bounded patience, reviews the issues when
CI finds them and tries to find their root cause, and ends in one of two
ways — an alert, or a merge that was explicitly authorized and earned.

---

## Configuration

Run `aether config show cairn --raw` (local wins), honour `enabled: false` by
stopping immediately, and let flags in $ARGUMENTS override both. Resolve
settings:

- `pr.watch_interval` — default interval if `--interval` not in $ARGUMENTS;
  fallback 120
- `pr.watch_timeout` — default timeout if `--timeout` not in $ARGUMENTS;
  fallback 45

If the CLI is absent, use the documented fallbacks and continue.

---

## Step 1 — Resolve the PR and its review state

```bash
gh pr view ${PR_NUMBER:+$PR_NUMBER} --json number,title,url,state,headRefName,baseRefName,reviewDecision,mergeStateStatus
```

No open PR for the current branch → say so and stop. Also run
`aether review status 2>/dev/null || true` — the merge step will need to know
whether the recorded review covers the current head.

State the watch up front, bounded and concrete:

```
Watching PR #<n> — <title>
  up to 45 minutes: 23 polls, 120 s apart
  merge: authorized (--merge) / not authorized — this watch ends in an alert
```

Say which it is before the first poll; an alert read after half an hour of
silence means nothing if the reader does not know a merge was never on the
table.

## Step 2 — The watch loop

One poll per shell call; wait between polls with the agent's own wait
mechanism — never a shell loop inside one call, never a busy wait. A loop
wedged into one call outlives the call's timeout and dies silently, which is
the failure this loop exists to prevent.

```bash
gh pr checks <n>
```

Do not read the exit code as the verdict: parse the output. A repo with no
workflows prints nothing at all — an empty check list is not a passing one;
say so and stop if that is what you see. `gh pr checks --watch` is not used:
it blocks until every check resolves, which can outlive the call.

Per poll, record: which checks were pending, which failed, which passed. When
everything passes, leave the loop. Append each poll's outcome to the marker
in Persist output as you go — a session killed mid-watch leaves the trail it
had written, not silence.

## Step 3 — Failing checks: find them, do not just forward them

On a failed poll:

```bash
gh run list --branch <head> --limit 5
gh run view <run-id> --log-failed
```

Review the issues and try to find the root cause — a flaky test, a race the
PR introduced, a dependency that moved — and report what you found, not just
the failing job's name. Then:

- **Fix in reach** (and no `--no-fix`): fix it, verify with
  `aether check` over the touched files, commit (small, conventional message,
  `/draft-commit` where available), push through the agent's normal push
  gates, and resume the watch against the new head.
- **Not in reach** (or `--no-fix`): report the failure and what the logs say,
  and stop. An alert that hides a known failure is worse than none.

A pushed fix has a consequence the merge step must honour: it resets the
review. The commits pushed are unreviewed; the earlier review record does
not cover the new head, and the merge step refuses until it does.

## Step 4 — Everything green: alert, or merge if authorized

The merge needs every one of these, no exceptions:

- `gh pr view --json reviewDecision` is `APPROVED` — `--merge` never
  overrides a missing approval
- the recorded review covers the **current** head (`aether review status`;
  a fix pushed during this watch invalidates the earlier record — re-run the
  review before merging)
- `--merge` was passed — merging is a destructive act on a shared system; it
  is authorized per PR, per watch, and never assumed because CI is green
- `mergeStateStatus` is mergeable

All true → merge with the repository's own convention — check how recent PRs
in the repo were merged (squash, merge commit) and use that method, saying
which:

```bash
gh pr merge <n> --squash   # or the repo's convention
```

Any false → alert and stop. The alert says exactly what is missing:

```
PR #<n> green: checks pass, review APPROVED — ready to merge (no --merge given)
```

A timeout alerts with the last known state and which checks were still
pending. Never merge on incomplete information, and never merge because the
timeout expired — a timeout is an alert, not a verdict.

## Persist output

Append to `.aether/out/CAIRN.md` (or `~/.aether/out/CAIRN.md` if the project
has no `.aether/`), with the header:

`# Watch — PR #<n> <title> — <current date>`

Wrap the report in a marker:

```
<!-- aether:watch date=<ISO 8601 UTC> scope=pr-<n> outcome=<merged|alerted|timeout|failed|empty> polls=<n> -->
# Watch — PR #<n> <title> — <date>

…poll outcomes, what failed and the root cause found, what was pushed, what
the merge decision was and why…
<!-- /aether:watch -->
```

Appending, never overwriting. Do **not** run `aether review record`: watching
is not reviewing, and the merge gate depends on that record meaning what it
says.
