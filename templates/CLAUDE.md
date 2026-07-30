<!-- aether:start -->
# aether suite — Claude Code discipline rules

aether coordinates four plugins across the full development lifecycle:
**plan → build → review → ship**

```
whetstone  →  bonsai  →  temper  →  cairn
 (plan)       (build)    (review)   (ship)
```

Each plugin covers one stage. The hooks fire in this order on `git commit`.
A single bypass (`# aether:skip`) silences all four.

A fifth plugin, **trellis**, sits outside the lifecycle: it has no hook and no
gate, and `/draft-config` writes the config the other four read.

---

## Configuration

One file per scope: `~/.aether/config` globally, `.aether/config` in a project,
with an `[<section>]` per plugin. Values resolve **per key**, so a project that
sets one threshold keeps the global value of every other.

```bash
aether config show [<section>]        # resolved values, and where each came from
aether config explain <section>.<key> # one key in full
aether config doctor                  # unknown keys, dead paths, trust state
aether config set temper.auto_nudge_lines 400
```

Two sections describe the repository rather than a plugin: `[project]` is things
to run (`test`, `lint`, `typecheck`, `build`, `coverage`), `[git]` is things to
write (`scopes`, `types`, `ticket`, `trailers`, `base`).

Prose for the critics goes in `rules.md` beside it, one section per command.

### Trust

`[project]` commands and `.aether/rules.md` are **ignored until the project is
trusted** — the two things a repo can do to a machine, one by being executed and
one by reaching a critic's context. Everything else applies immediately.

```bash
aether trust           # shows what you are consenting to, then records it
aether trust status    # none | ok | changed
```

Hand-editing either file asks again; `aether config set` re-hashes automatically.

If a critic reports that project rules were skipped, that is this — say so in the
report rather than reviewing with less context than the file implies.

---

## Planning discipline (whetstone)

Before implementing any non-trivial change, present a plan and run `/critique-plan`
on it. Catch blockers at plan time — not at review time (temper) and not at
incident time.

### What counts as a plan that needs critique

Run `/critique-plan` automatically when the proposed work:

- Spans more than 2 files
- Introduces a new module, class, or public API
- Involves a database migration or schema change
- Touches authentication, permissions, or secrets handling
- Changes a function signature that has external callers
- Was requested with words like "implement", "build", "add", "refactor", "migrate"

Skip the critique (use `# whetstone:skip` or just proceed) when:

- Fixing a typo or comment
- Updating a single config value with no downstream effect
- Writing a new file with no importers yet (pure addition, no breakage possible)
- The user explicitly says "quick fix" or "just change X"

### Auto-trigger rules

After **presenting any plan**, run `/critique-plan` immediately — do not wait for
a prompt. Surface blockers before asking the user to approve.

After **any user feedback on a plan** (scope change, added constraint, pushback
on an approach), update the plan file and re-run `/critique-plan` on the revised
plan before presenting it for approval.

After **a temper Design finding** that leads to a renamed symbol or restructured
module — re-critique the plan if the structural change is significant. A Design
finding that causes architectural drift is a new plan, not a patch.

After **a bonsai tool reports unexpected references** during a dry-run — surface
that as new information in the plan and re-run `/critique-plan`. Unexpected blast
radius is a plan-level concern, not just a code-level one.

### Post-critique gate

If blockers (🔴) are found, do NOT proceed to implementation. Present the
blockers clearly and wait. Only proceed when:

- The user resolves the blockers and the revised plan passes re-critique, or
- The user explicitly says `override blockers` (record this in the critique file)

If only 🟡 or 🟢 findings remain, proceed — but note any 🟡 items in the
plan file as known risks to revisit during temper review.

### Plan file conventions

Plans live wherever they are written — `.claude/plans/` in a project, or
`~/.claude/plans/`, which is where Claude Code's plan mode puts them. The critique
lives **inside the plan it critiques**:

```markdown
…the plan…

<!-- aether:critique sha=3f9a1c… date=2026-07-30 blockers=0 -->
## Critique
…the report…
<!-- /aether:critique -->
```

That is the only file writable in plan mode, so it is the only place a critique made
there can be recorded. It is also per plan: one shared `CRITIQUE.md` meant critiquing
one plan satisfied the gate for every other.

`sha` is the hash of the plan with the critique block removed, so the gate can tell a
plan that changed from one that was merely re-saved. `aether plan status` reports which
plan the gate sees and whether it considers it critiqued.

Generated review output still lives under `.aether/out/`:

```
.aether/out/CRITIQUE.md   accumulating history across plans
.aether/out/TEMPER.md     /critique-diff output
```
### Severity handoff

| whetstone finding | What to do |
|---|---|
| 🔴 architecture blocker | Resolve before writing a single line |
| 🔴 missing dependency or unclear scope | Resolve before writing a single line |
| 🟡 naming or design concern | Note in plan — hand to bonsai if it involves symbol renames |
| 🟡 risk concern | Note in plan — hand to temper for diff-time review after implementation |
| 🟢 minor | Note in plan — fix opportunistically during implementation |

### Skipping

To skip whetstone for a specific plan, include `# whetstone:skip` in the plan heading.
To skip all suite hooks for a plan, use `# suite:skip` instead.
For a one-off skip without modifying the plan, say `/critique-plan --off`.

---

## AST refactoring with bonsai

When editing `.py`, `.ts`, `.tsx`, `.js`, or `.jsx` files, prefer bonsai MCP
tools over text tools. Text tools miss re-exports, aliased imports, and type
references — they silently break code when renaming or moving symbols.

### Tool reference

| Operation | Python | TypeScript |
|---|---|---|
| Find all references | `pyfindrefs` | `tsfindrefs` |
| Rename a symbol | `pyrename` | `tsrename` |
| Move a file (rewrites imports) | `pymove` | `tsmove` |
| Move a symbol between modules | `pymovesymbol` | `tsmovesymbol` |
| Change a function signature | `pysignature` | `tssignature` |
| Find dead code | `pyfindunused` | — |
| Regex search (AST-aware) | `pygrep` | — |

Always request `--dry-run` first on any mutating tool. Review the diff, then apply.

### When to reach for bonsai proactively

Reach for bonsai — without waiting for the hook to nudge — in these situations:

- **Before deleting a function or class**: run `pyfindunused` first to confirm
  it has no live references. Deletion without this check silently orphans callers.
- **After a temper Design finding about naming**: if temper flags a misleading
  name, use `pyrename` / `tsrename` rather than sed — the rename must propagate
  everywhere, not just the definition site.
- **After a temper Correctness finding about a function signature**: use
  `pysignature` to propagate the fix to all call sites in one pass.
- **When this session has touched more than 3 files in the same module**: run
  `pyfindunused` across the module before committing — incremental edits
  across multiple files often leave orphaned symbols behind.
- **When moving a file for any reason**: always use `pymove` / `tsmove`, never
  raw `mv`. Even for untracked files — if they will be imported later, moving
  them with bonsai builds the correct import path from the start.

### When NOT to use bonsai

- New files with no importers yet — raw file creation is fine
- Config files, Markdown, JSON, YAML — bonsai operates on source ASTs only
- Comment-only or docstring-only changes — no symbol impact, text edit is fine
- Exploratory `grep` to understand a codebase — use raw grep, no structural
  change is being made

---

## Code review discipline (temper)

### When to run /critique-diff

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

### When to run /critique-pr

`/critique-diff` reviews what you are about to commit; `/critique-pr` reviews what
someone is about to merge. Run it once the PR is open and before merging when:

- The PR touches more than one subsystem, or any critical path listed above
- Commits landed after the description was written — the description is then the most
  likely thing in the PR to be wrong
- CI is green and the PR *looks* ready, which is exactly when nobody re-reads it

It runs temper's same four critics over the whole PR diff, plus a fifth that only makes
sense for a PR: whether the description still matches the code. An omitted change is
more dangerous than an inaccurate one — a reviewer who trusts the description will not
go looking for what it does not name.

### Severity contract

🔴 Blocker      — do not push; fix first
🟡 Significant  — fix before the next session or document the exception
🟢 Minor        — fix when convenient; still worth tracking

Never bypass a 🔴 finding without a written reason in the commit message.

---

## Git narration with cairn

Cairn writes commit messages, PR descriptions, changelogs, and standup summaries
from diffs. Reach for it at every git boundary — before committing, before
pushing, and after shipping.

### Which command for which moment

| Moment | Command |
|---|---|
| About to `git commit` | `/draft-commit` — generate message from staged diff |
| About to `git push` | `/draft-pr` — generate PR title and description |
| PR description is stale | `/draft-pr --apply` — regenerate it and push it to the PR |
| After temper finds no blockers | `/draft-commit` immediately — prime moment |
| After a version bump in any manifest | `/draft-changelog` |
| After a sprint, milestone, or release | `/draft-summary --format=slack` or `--format=paragraph` |
| Multi-area staged diff | `/draft-commit` — cairn will suggest splitting if needed |

### Proactive triggers

- **After temper completes with no 🔴 findings**: run `/draft-commit`. The review is fresh — best moment to write the commit message.
- **After any bonsai rename or move**: the diff will be large and noisy. `/draft-commit` reads the intent, not the line count.
- **Before pushing a branch that diverged more than 3 commits from base**: run `/draft-pr` while context is live.
- **After any session that touched more than 5 files**: run `/draft-summary` before closing.

### Changelog and versioning rules

Every non-trivial change requires a CHANGELOG.md entry:

- Adding a feature → `### Added`
- Changing behaviour → `### Changed`
- Fixing a bug → `### Fixed`
- Removing something → `### Removed`

---

## Suite bypass reference

Full specification: [BYPASS.md](https://github.com/ValentinFigue/aether/blob/main/BYPASS.md)

| Marker | Effect |
|---|---|
| `# aether:skip` | Silence all suite hooks |
| `# suite:skip` | Alias for aether:skip |
| `# whetstone:skip` | Silence whetstone gate only |
| `# bonsai:skip` | Silence bonsai gate only |
| `# temper:skip` | Silence temper gate only |
| `# cairn:skip` | Silence cairn gate only |

Append to any bash command as a **trailing** inline comment — the marker must be the
last thing on the line, after a `#` that starts a word and is outside quotes. Bash
ignores comments at runtime. A marker inside a quoted string is not a bypass, so
`git commit -m "docs: explain # temper:skip"` still runs every gate.
<!-- aether:end -->
