# aether — discipline rules for other agents (Vibe Code, Codex)

This file is the portable equivalent of aether's Claude Code block. On Claude
Code, hooks enforce the checkpoints below automatically; here nothing
intercepts a tool call, so this file plus the installed aether skills are the
whole discipline. Invoke them deliberately at each checkpoint — nothing will
nudge you if you forget.

The lifecycle: **plan → build → review → ship**

```
critique-plan → bonsai-first → critique-diff / critique-pr → draft-commit / draft-pr
   (whetstone)      (bonsai)           (temper)                     (cairn)
```

`draft-config` (trellis) sits outside the lifecycle: it writes the
`.aether/config` the others read.

Every skill degrades gracefully without the `aether` CLI — config reads fall
back to documented defaults — so these rules work on a machine where aether was
never installed. The one write path, `draft-config`'s `aether config set`, needs
the CLI and says so.

---

## Planning — `critique-plan`

Before implementing any non-trivial change, present a plan and run
`critique-plan` on it. Catch blockers at plan time — not at review time and not
at incident time.

Run it when the proposed work:

- Spans more than 2 files
- Introduces a new module, class, or public API
- Involves a database migration or schema change
- Touches authentication, permissions, or secrets handling
- Changes a function signature that has external callers

Skip it for typo fixes, single config values with no downstream effect, and
pure additions with no importers.

After presenting a plan, run the critique immediately rather than waiting to be
asked. After user feedback changes the scope, re-critique the revised plan.

If 🔴 blockers are found, do not proceed to implementation. Present the
blockers and wait for the user to resolve them or explicitly override.

---

## Building — `bonsai-first`

When editing `.py` / `.ts` / `.tsx` files, prefer the bonsai AST tools over
`sed`/`grep`/`awk` for structural operations (rename, move, find references,
signature changes) — text tools miss imports, re-exports, and type references.
This needs the bonsai MCP servers; if they are not configured, say so and fall
back to text tools, stating the risk.

Reach for it proactively:

- Before deleting a function or class — confirm it has no live references first
- After any rename or move — the change must propagate everywhere, not just the
  definition site
- When this session has touched more than 3 files in one module — check for
  orphaned symbols before committing

Always dry-run a mutating bonsai tool and review the diff before applying.

---

## Reviewing — `critique-diff`, `critique-pr` and `interview-pr`

`critique-diff` reviews what you are about to commit. Run it before any
`git commit` or `git push` when:

- The diff touches more than 10 files or 200 lines
- A new module, class, or file was created
- Any function signature changed
- Always, regardless of size, when the diff touches authentication or
  permissions, database migrations, public API contracts, or secrets

`critique-pr` reviews what someone is about to merge. Run it once the PR is
open and before merging when the PR spans more than one subsystem, when commits
landed after the description was written, or when CI is green and the PR
*looks* ready — exactly when nobody re-reads it.

`interview-pr` is for the PRs a one-shot review fails on: too complex to follow,
heading for "5K changes: LGTM". It walks the reviewer through the PR area by
area, asks their opinion one question at a time, and drafts every agreed change
request as a PR comment with context — nothing reaches the PR during the
interview; at the end the reviewer is asked which drafts to post. Run it
deliberately when asked to be walked through a PR; it is interactive and never
advances before the reviewer answers.

Severity contract:

- 🔴 Blocker — do not push; fix first
- 🟡 Significant — fix before the next session or document the exception
- 🟢 Minor — fix when convenient; still worth tracking

Never bypass a 🔴 finding without a written reason in the commit message.

---

## Shipping — `draft-commit`, `draft-pr`, `draft-changelog`, `draft-summary`

| Moment | Command |
|---|---|
| About to `git commit` | `draft-commit` |
| About to open or update a PR | `draft-pr` (`--apply` to publish it) |
| After a version bump in any manifest | `draft-changelog` |
| After a sprint, milestone, or release | `draft-summary` |

Prime moments: run `draft-commit` right after a review comes back clean, and
`draft-pr` while the branch's context is still live. Neither command commits,
pushes, or writes anything unless `--apply` was passed.

---

## What is different without Claude Code

- No hooks fire, so nothing enforces the checkpoints above — the agent reading
  this file is the enforcement.
- The `# aether:skip` / `# temper:skip` trailing-comment bypass markers do
  nothing here; they are hook directives. Skipping is a decision you make by
  simply not invoking the skill.
- There is no plan-mode gate: `critique-plan` is invoked on the plan you
  present, wherever it lives. Write plans to `.aether/plans/` in the project —
  aether's own, agent-agnostic plans directory — so `aether plan status` and
  the critique machinery can see them; Claude Code's plan mode still works
  from `.claude/plans/`.
