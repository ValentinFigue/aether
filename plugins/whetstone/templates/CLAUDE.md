<!-- whetstone:start -->
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
### Severity handoff to the rest of the suite

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
<!-- whetstone:end -->
