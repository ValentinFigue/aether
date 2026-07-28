<!-- whetstone:start -->
## Planning discipline (whetstone)

Before implementing any non-trivial change, present a plan and run `/autocritic`
on it. Catch blockers at plan time — not at review time (temper) and not at
incident time.

### What counts as a plan that needs critique

Run `/autocritic` automatically when the proposed work:

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

After **presenting any plan**, run `/autocritic` immediately — do not wait for
a prompt. Surface blockers before asking the user to approve.

After **any user feedback on a plan** (scope change, added constraint, pushback
on an approach), update the plan file and re-run `/autocritic` on the revised
plan before presenting it for approval.

After **a temper Design finding** that leads to a renamed symbol or restructured
module — re-critique the plan if the structural change is significant. A Design
finding that causes architectural drift is a new plan, not a patch.

After **a bonsai tool reports unexpected references** during a dry-run — surface
that as new information in the plan and re-run `/autocritic`. Unexpected blast
radius is a plan-level concern, not just a code-level one.

### Post-critique gate

If blockers (🔴) are found, do NOT proceed to implementation. Present the
blockers clearly and wait. Only proceed when:

- The user resolves the blockers and the revised plan passes re-critique, or
- The user explicitly says `override blockers` (record this in the critique file)

If only 🟡 or 🟢 findings remain, proceed — but note any 🟡 items in the
plan file as known risks to revisit during temper review.

### Plan file conventions

Store plans and critiques in `.claude/plans/`:

```
.claude/plans/
├── <plan-name>.md   # the current plan (one file per plan)
└── CRITIQUE.md      # the latest /autocritic output (append with date headers)
```

The hook (`enforce-whetstone.sh`) detects stale critiques by comparing the
modification time of the newest plan file against `CRITIQUE.md`. Always write
critiques to `.claude/plans/CRITIQUE.md` so the hook can find them.

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
For a one-off skip without modifying the plan, say `/autocritic --off`.
<!-- whetstone:end -->
