Critique a diff before commit or push — four critics, severity-rated (temper).

# critique-diff

## Configuration

Resolve settings in three steps, lowest to highest priority:

**Step 1 — Read config files:**
- Check `~/.claude/temper.config` (global defaults)
- Check `./temper.config` (local overrides; wins over global)

Each file is key-value, one entry per line:
```
enabled: true
critics: correctness, design, risk, coverage
skip:
severity: red, yellow
diff: staged
auto_nudge_lines: 200
auto_nudge_files: 10
critical_paths: *auth*, *permission*, *token*, migrations/, *alembic*, *.sql, *schema*, *secret*, *credential*, *.env
```

**Step 2 — Parse `$ARGUMENTS`** (overrides config files):

| Flag | Effect |
|------|--------|
| `--only=correctness,risk` | Run only these critics |
| `--skip=coverage` | Run all defaults except the named one(s) |
| `--severity=red` | Report only 🔴 findings |
| `--severity=red,yellow` | Report 🔴 and 🟡 findings |
| `--diff=staged` | Review staged changes (default) |
| `--diff=unstaged` | Review unstaged working-tree changes |
| `--diff=all` | Review all changes since HEAD |
| `--diff=<commit-ish>` | Review diff between that commit and HEAD |
| `--target=<file>` | Scope review to a single file |
| `--off` | Print "temper disabled for this run." and stop |
| `--help` | Print this flag table and stop |

If `$ARGUMENTS` is empty and no config files exist, run all four defaults (`correctness`, `design`, `risk`, `coverage`) and show all severities.
If an unrecognised flag is passed, print a warning and fall back to defaults.

**Step 3 — Check enabled state:**
If `enabled: false` is set in the resolved config, print "temper is disabled for this project. Run `temper enable` to re-enable." and stop immediately.

---

## Diff gathering

**Step 1 — Resolve diff target:**

Based on the `--diff` flag or `diff:` config key (default: `staged`):

- `staged` → run `git diff --staged`
- `unstaged` → run `git diff`
- `all` → run `git diff HEAD`
- `<commit-ish>` → run `git diff <commit-ish>..HEAD`

Fallback: if `--diff=staged` (or default) and `git diff --staged` is empty, automatically fall back to `git diff HEAD~1 HEAD` (most recent commit). Inform the user: "Staging area is empty — reviewing last commit instead."

**Step 2 — Empty diff check:**
If the diff is still empty after the fallback, print: "No changes found to review." and stop.

**Step 3 — Apply `--target` filter:**
If `--target=<file>` was specified, scope the diff to that file: `git diff [target] -- <file>`.

**Step 4 — Collect supporting context:**
- Run `git log --oneline -5` for recent history
- List modified files and detect primary language(s)
- Note whether test files appear in the diff
- Count total lines changed and files touched

---

## Secrets scan

Before critiquing, scan the diff output for known credential patterns:
- Known prefixes: `sk-`, `AKIA`, `ghp_`, `ghs_`, `-----BEGIN`
- High-entropy strings (20+ chars of mixed alphanumerics) adjacent to words: `key`, `secret`, `token`, `password`, `credential`, `api`

If patterns are found, print a warning block at the top of the output and include it in TEMPER.md. Continue with critique (non-blocking).

---

## Critic 1 — Correctness (run if: `correctness` selected or no arguments)

You are a senior engineer focused on logic and runtime safety.

Review the diff for:
- Logic errors, incorrect conditionals, off-by-one mistakes
- Null/undefined dereferences and missing nil checks
- Unhandled error paths and exception cases
- Incorrect assumptions about input shape, type, or range
- Race conditions or shared-state bugs introduced by the change

Rate each finding: 🔴 blocker / 🟡 significant / 🟢 minor

---

## Critic 2 — Design (run if: `design` selected or no arguments)

You are a senior engineer who values clarity and simple structure.

Review the diff for:
- Unnecessary coupling or leaky abstractions
- Naming that misleads (the name says A, the code does B)
- Duplication that belongs in a shared utility
- Premature complexity or over-engineering for the current scope
- Functions or classes taking on too many responsibilities

Rate each finding: 🔴 blocker / 🟡 significant / 🟢 minor

---

## Critic 3 — Risk (run if: `risk` selected or no arguments)

You are a cautious senior engineer focused on what can break in production.

Review the diff for:
- Security vulnerabilities: injection, auth bypass, insecure defaults, trust boundary violations
- Data loss or corruption scenarios introduced by the change
- Breaking changes to public APIs, contracts, or user-facing behaviour
- Missing observability: no logs, no metrics, no error context for new failure paths
- Anything that would be a bad surprise at 2am

Rate each finding: 🔴 blocker / 🟡 significant / 🟢 minor

---

## Critic 4 — Coverage (run if: `coverage` selected or no arguments)

You are a QA engineer and testing advocate.

Review the diff for:
- New code paths not covered by tests (functions, branches, error handlers)
- Existing tests that now exercise changed logic — are they still valid?
- Edge cases introduced by the change that have no test
- Changes that make code harder to test (tight coupling, hidden dependencies)

Rate each finding: 🔴 blocker / 🟡 significant / 🟢 minor

---

## Report format

After all selected passes, output:

### Review report

| # | Critic      | Severity | Finding | Recommendation |
|---|-------------|----------|---------|----------------|
| 1 | Correctness | 🔴       | …       | …              |
| … |             |          |         |                |

**Blockers:** N
**Significant:** N
**Minor:** N

> If no findings at all: state "Nothing to flag — looks good to ship."
> If no blockers or significant findings: state "No critical issues. Minor observations only." and list them briefly.

Do not rewrite the code. Surface findings only. The developer decides what to act on.

---

## Gate

After the report:

- **If any 🔴 findings exist:**
  > **Blocked.** Resolve the 🔴 findings above or append `# temper:skip` to your `git push` command to explicitly bypass.

- **If all findings are 🟡 or 🟢:**
  > Output a one-line summary, e.g.: _"3 findings (0 🔴, 2 🟡, 1 🟢). Good to ship with the above addressed."_

---

## Persist output

After printing the report, determine the target directory:
- If `.claude/plans/` exists in the project root → write to `.claude/plans/TEMPER.md`
- Else if `~/.claude/plans/` exists → write to `~/.claude/plans/TEMPER.md`
- Otherwise create `.claude/plans/` in the project root and write there

Prepend a header: `# Review — <diff target description> — <current date>`

If `TEMPER.md` already exists at the resolved path, **append** rather than overwrite, accumulating a history of reviews over time.
