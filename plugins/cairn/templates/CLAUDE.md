## Git narration with cairn

Cairn writes commit messages, PR descriptions, changelogs, and standup summaries
from diffs. Reach for it at every git boundary — before committing, before
pushing, and after shipping.

### Which command for which moment

| Moment | Command |
|---|---|
| About to `git commit` | `/draft-commit` — generate message from staged diff |
| About to `git push` | `/draft-pr` — generate PR title and description |
| PR is open and under CI | `/watch-pr` — poll the checks, triage failures, alert or merge |
| After temper finds no blockers | `/draft-commit` immediately — prime moment |
| After a version bump in any manifest | `/draft-changelog` |
| After a sprint, milestone, or release | `/draft-summary --format=slack` or `--format=paragraph` |
| Multi-area staged diff | `/draft-commit` — cairn will suggest splitting if needed |

### CI watch (watch-pr)

Between "PR open + reviewed" and "merge", `/watch-pr` owns the wait: sleep/poll
`gh pr checks` with bounded patience — never the blocking `--watch` form, never a
busy loop — and when checks fail, review the issues and try to find their root cause,
not just their names. A fix in reach goes through the normal verify/commit/push gates
and resumes the watch; anything else alerts and stops. The ending is an alert by
default, or a merge that requires all of: APPROVED reviewDecision, a recorded review
covering the *current* head (a mid-watch fix invalidates the earlier record), and an
explicit `--merge` for this PR. A timeout is an alert, not a verdict; an empty check
list is not a passing one.

### Proactive triggers — reach for cairn without waiting for a nudge

- **After temper completes with no 🔴 findings**: run `/draft-commit` on the
  staged diff. The review is fresh, the context is live — this is the best
  moment to write the commit message.

- **After any bonsai rename or move**: the diff will be large and
  mechanically noisy (`pyrename` touches every call site). `/draft-commit`
  reads the intent behind the change, not the line count —
  it will write `refactor(auth): rename TokenValidator → TokenVerifier`
  rather than `changed 47 files`.

- **Before pushing a branch that diverged more than 3 commits from base**:
  run `/draft-pr` to draft the PR description while the context is still live.
  Do not wait until after the push.

- **When a whetstone 🟡 risk finding was noted in the plan but not resolved**:
  reference it explicitly in the commit message via `/draft-commit`. The commit
  message is the right place to document a known accepted risk.

- **After any session that touched more than 5 files**: run `/draft-summary`
  before closing the session. It costs nothing and keeps the trail readable.

### Commit message quality contract

Never write `git commit -m "fix"`, `"update"`, `"wip"`, or any single-word
message. If there is no time to run `/draft-commit`, the minimum acceptable
message is a conventional commit with a non-trivial description:

    fix(auth): prevent token acceptance past expiry when clock-skew > 30s

If `/draft-commit` produces a message that spans multiple logical areas
(e.g. `feat(auth): ... and fix(docs): ...`), follow its suggestion to split
into separate commits before running `git commit`.

### Changelog and versioning rules

Every non-trivial change requires a CHANGELOG.md entry. The hook detects
version bumps in manifest files and nudges automatically — but do not wait
for the nudge:

- When adding a feature → add under `### Added`
- When changing behaviour → add under `### Changed`
- When fixing a bug → add under `### Fixed`
- When removing something → add under `### Removed`

Dogfooding rule: every commit to a cairn-managed repo should use
`/draft-commit` to generate its own message.

### Documentation sync rules

Any change to a `.claude/commands/draft-*.md` file must be reflected in
README.md before the change is committed:

- Flag added or removed → update the quick reference table
- Output format changes → regenerate the sample output block
- Install steps change → update the Install section

The hook will not catch these automatically — this is a discipline rule.

### Testing rules

Before marking any implementation task complete, verify the command works
end-to-end: stage a real change in a test repo, run the relevant cairn
command, and confirm the output is correct.

### Skipping

Append `# cairn:skip` to any git command to silence the nudge for that run.
Use `# suite:skip` to silence all suite hooks simultaneously.
