<!-- temper:start -->
# Code review discipline (temper)

## When to run /temper

Run `/temper` before any `git commit` or `git push` when any of the following is true:

**Scope triggers:**
- The diff touches more than 10 files or 200 lines
- A new module, class, or file was created
- Any function signature was changed
- A new dependency was added to pyproject.toml, package.json, or similar

**Critical path triggers — always run /temper regardless of diff size:**
- Authentication or authorisation code (`*auth*`, `*permission*`, `*token*`)
- Database migrations (`migrations/`, `*alembic*`, `*.sql`)
- Public API contracts (`*routes*`, `*endpoints*`, `*schema*`)
- Secrets and credentials (`*secret*`, `*credential*`, `*.env`, `*.env.*`)

**Post-bonsai gate:**
After any bonsai refactoring tool completes (pyrename, pymove, pymovesymbol, pysignature,
tsrename, tsmove, tsmovesymbol, tssignature), remind the user to run
`/temper --diff=all` before committing. Structural changes are high-risk even when
individually small.

**Session scope awareness:**
If this Claude Code session has involved more than 5 file edits, proactively suggest
`/temper` before the user runs any git command, even if they haven't asked for a review.

## Bypass

Append `# temper:skip` to your `git push` or `git commit` command to bypass the hook.
Never bypass a 🔴 finding without a written reason in the commit message.

## Severity contract

🔴 Blocker      — do not push; fix first
🟡 Significant  — fix before the next session or document the exception
🟢 Minor        — fix when convenient; still worth tracking
<!-- temper:end -->
