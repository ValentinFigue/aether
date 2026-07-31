<!-- temper:start -->
# Code review discipline (temper)

## When to run /critique-diff

Run `/critique-diff` before any `git commit` or `git push` when any of the following is true:

**Scope triggers:**
- The diff touches more than 10 files or 200 lines
- A new module, class, or file was created
- Any function signature was changed
- A new dependency was added to pyproject.toml, package.json, or similar

**Critical path triggers — always run /critique-diff regardless of diff size:**
- Authentication or authorisation code (`*auth*`, `*permission*`, `*token*`)
- Database migrations (`migrations/`, `*alembic*`, `*.sql`)
- Public API contracts (`*routes*`, `*endpoints*`, `*schema*`)
- Secrets and credentials (`*secret*`, `*credential*`, `*.env`, `*.env.*`)

**Post-bonsai gate:**
After any bonsai refactoring tool completes (pyrename, pymove, pymovesymbol, pysignature,
tsrename, tsmove, tsmovesymbol, tssignature), remind the user to run
`/critique-diff --diff=all` before committing. Structural changes are high-risk even when
individually small.

**Session scope awareness:**
If this Claude Code session has involved more than 5 file edits, proactively suggest
`/critique-diff` before the user runs any git command, even if they haven't asked for a review.

## Bypass

Append `# temper:skip` to bypass only the temper hook, or `# suite:skip` to bypass all
suite hooks (temper, cairn, whetstone) in one annotation.
Never bypass a 🔴 finding without a written reason in the commit message.

## Severity contract

🔴 Blocker      — do not push; fix first
🟡 Significant  — fix before the next session or document the exception
🟢 Minor        — fix when convenient; still worth tracking

### When to run /critique-pr

`/critique-diff` reviews what you are about to commit; `/critique-pr` reviews what
someone is about to merge. Run it once the PR is open and before merging when:

- The PR touches more than one subsystem, or any critical path listed above
- Commits landed after the description was written — the description is then the most
  likely thing in the PR to be wrong
- CI is green and the PR *looks* ready, which is exactly when nobody re-reads it

It runs temper's same five critics over the whole PR diff, plus a sixth that only makes
sense for a PR: whether the description still matches the code. An omitted change is
more dangerous than an inaccurate one — a reviewer who trusts the description will not
go looking for what it does not name.
<!-- temper:end -->
