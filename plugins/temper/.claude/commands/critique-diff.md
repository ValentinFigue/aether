Critique a diff before commit or push — five critics, severity-rated (temper).

# critique-diff

## Configuration

Resolve settings in three steps, lowest to highest priority:

**Step 1 — Read config files:**
Run:

```bash
aether config show temper --raw 2>/dev/null || true
```

Each line is `key: value`, already resolved — `~/.aether/config`, then the
project's `.aether/config`, per key, with declared defaults filled in. If it
prints nothing, use the defaults documented below and continue.

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

If `$ARGUMENTS` is empty and no config files exist, run all five defaults (`correctness`, `design`, `risk`, `coverage`, `docs`) and show all severities.
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

## Measurement pass (run before the critics)

Everything below is optional and depends on `[project]` config. With none set, say so
once and fall back to reading the diff — never imply a check ran.

`[project]` holds shell commands, so **you do not run them yourself.** `aether check`
is the only thing that executes them: it resolves which monorepo area each changed
file belongs to, runs each area's commands in that area's directory, and refuses
outright if the project is untrusted.

```bash
git diff --name-only --staged            # or --diff=all / the target
aether check <changed files…> --raw 2>/dev/null || true
aether rules 2>/dev/null || true
```

`--raw` gives one line per check, tab-separated — `area`, `key`, `status`, `command`:

```
project:web	lint	ok	bun run lint-ci
project:web	typecheck	fail	bun run tsc
project:backend	-	skipped
```

| status | meaning |
|---|---|
| `ok` | it ran and passed |
| `fail` | it ran and failed — feed the output to the critic named below |
| `skipped` | that area exists but this diff does not touch it |
| `missing` | the area's directory is gone; a configuration problem, not a finding |

Re-run one area without `--raw` to see the failure output: `aether check <area>`.

Feed each result to its critic: `typecheck`, `lint` and `format` → **Correctness**;
`test` and `coverage` → **Coverage**; `check.*` → **Correctness**, named as the
project-specific invariant it is.

Rules for this pass:

- **Report what ran, per area.** Name the command and its status. "Tests pass"
  without naming the command is a guess, and in a monorepo it is also ambiguous
  about *which* tests.
- **Name the areas you skipped.** A reviewer needs to know that the backend was not
  checked because the diff did not touch it — not to assume it was.
- A command that could not start is a configuration problem, not a finding about the
  diff. Report it once and move on; `aether config doctor` diagnoses it.
- If `aether check` says the project is untrusted, say so in the report header and
  read the diff instead. Do not work around it.
- Never invent a command, and never run one yourself.

If `aether rules` says project `rules.md` was **not** read, put that in the header
verbatim — the user is getting less context than the file suggests.

---

## Critic 1 — Correctness (run if: `correctness` selected or no arguments)

You are a senior engineer focused on logic and runtime safety.

**If the measurement pass ran `typecheck`, `lint` or `format`, start from their
output.** A real violation with a file and line beats an inferred one. Report
each with the command that produced it. Then review the diff for what a tool
cannot see:
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

**If the measurement pass ran `test`, start from the result.** A failing test is
a 🔴 with the failure output quoted — not a judgement call. If `coverage` ran and
`coverage_min` is set, a figure below it is 🟡 with both numbers stated. If
neither was configured, say so in one line and infer from the diff as below.

Review the diff for:
- New code paths not covered by tests (functions, branches, error handlers)
- Existing tests that now exercise changed logic — are they still valid?
- Edge cases introduced by the change that have no test
- Changes that make code harder to test (tight coupling, hidden dependencies)

Rate each finding: 🔴 blocker / 🟡 significant / 🟢 minor

---

## Critic 5 — Documentation (run if: `docs` selected or no arguments)

You are the person who will read this project's documentation next week and act on it.

**If `aether check` ran a `docs` step, start from its findings** rather than
re-deriving them — it has already checked what is mechanically checkable (commands and
flags that do not exist, config examples whose values are invalid, prose contradicting
the declared `[project]` commands, dead links). Your job is the half it cannot reach.

For each behaviour this diff changes — a flag, a subcommand, a config key or its
default, an exit code, a matcher, a threshold, a printed message, a public signature —
find the documentation that describes it and say whether it is still true:

- **A sentence that is now false** is 🔴. Not "incomplete": false. A reader who trusts
  it will confidently do the wrong thing, which is worse than finding nothing.
- **Sample output that no longer matches** what the command prints — a fenced
  transcript is a claim about behaviour, and nothing re-runs it.
- **A section describing a state the code can no longer reach**, including a roadmap
  item for something this diff just shipped.
- **Documentation that is merely missing** for something new is 🟡, unless the thing is
  a breaking change, in which case it is 🔴.

Search for the *string* you changed rather than the file you expect: `git grep` the old
flag, key or path. Documentation drift hides in the file nobody thought to open.

**Say nothing when there is nothing.** If this diff changes no documented behaviour,
report that in one line and move on. A critic that manufactures a finding on every
review is one people learn to skip.

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
Then **record that the review happened**, so anything downstream can tell reviewed work
from unreviewed:

```bash
aether review record --scope=staged     # or --scope=all, or the ref you reviewed
```

Run it with the scope you actually reviewed. It hashes the diff content rather than the
commit, so the record survives committing, amending and rebasing — and
`aether review status` can then answer whether what is about to be pushed has been
reviewed, which nothing could answer before. Skip it only if you reviewed nothing.

- If the project has a `.aether/` directory → write to `.aether/out/TEMPER.md`
- Otherwise → write to `~/.aether/out/TEMPER.md`

Create the directory if it does not exist. Pre-1.1 installs wrote to
`.claude/plans/TEMPER.md`; if that file exists and `.aether/out/` does not, keep
appending there rather than starting a second history — `aether migrate` moves it.

Prepend a header: `# Review — <diff target description> — <current date>`

**Wrap the report in a marker**, so it can be read back individually:

```
<!-- aether:review date=<ISO 8601 UTC, e.g. 2026-07-31T12:04Z> scope=<staged|all|the ref> blockers=<n> significant=<n> minor=<n> -->
# Review — <target> — <date>

…the report…
<!-- /aether:review -->
```

`aether review show` and `aether review list` read these. Reports written before the
marker existed are still found by their heading, but carry no scope and no time of day —
which is why two reviews on the same day used to be indistinguishable.

The counts in the marker must match the ones in the report body. They exist so the list
view does not have to parse prose: across one real history the same three numbers appear
as `**Blockers:** 0`, `**Blockers:** 0 | **Significant:** 3 | **Minor:** 4`, and
`**Blockers:** 0 — … — Good to ship`, which is not a format anything should depend on.


If `TEMPER.md` already exists at the resolved path, **append** rather than overwrite, accumulating a history of reviews over time.
