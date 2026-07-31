# temper

Harden your code before it ships. Temper runs four adversarial critics against your diff — catching logic errors, design drift, production risks, and coverage gaps at review time, not incident time.

It is the symmetric counterpart to [whetstone](../whetstone/): where whetstone critiques *plans*, temper critiques *diffs*.

> Tempering is the hardening process applied *after* forging. The metal has been shaped — now we make sure it holds.

---

## What it does

Run `/critique-diff` before committing or pushing. Temper reads your staged diff (or any diff you point it at), runs four critic personas against the code, and produces a structured review with severity ratings:

```
### Review report

| # | Critic      | Severity | Finding                                         | Recommendation                        |
|---|-------------|----------|-------------------------------------------------|---------------------------------------|
| 1 | Correctness | 🔴       | Missing nil check on user.email before send()   | Add guard: if user.email is None: ...  |
| 2 | Risk        | 🟡       | New endpoint has no rate limiting               | Add @rate_limit decorator             |
| 3 | Coverage    | 🟢       | Happy path tested but empty-list case is not    | Add test for empty input              |

Blockers: 1
Significant: 1
Minor: 1
```

If blockers are found, temper gates the push until they're resolved.

---

## The four critics

| Critic | Focus |
|--------|-------|
| **Correctness** | Logic errors, null dereferences, off-by-ones, unhandled errors |
| **Design** | Coupling, misleading names, duplication, premature complexity |
| **Risk** | Security vulnerabilities, data loss, breaking API changes, missing observability |
| **Coverage** | Untested paths, invalidated tests, untestable code |

---

## Install

temper ships as part of the [aether suite](../../README.md). Clone once, then install
either the whole suite or temper alone.

### Whole suite — whetstone, bonsai, temper and cairn behind one hook

```bash
git clone https://github.com/ValentinFigue/aether
cd aether && bash install.sh --global --claude-md
```

### temper alone — global

```bash
git clone https://github.com/ValentinFigue/aether
cd aether/plugins/temper && bash install.sh global
```

The installer reads everything from the clone, so keep it around — or re-run it after
moving it. There is no `curl | bash` one-liner: the script copies files out of the
repository and cannot work when piped.

### Local install (this project only)

```bash
bash install.sh
```

### With proactive CLAUDE.md rules

Adds behavioral guidelines to your CLAUDE.md that teach Claude Code to proactively suggest `/critique-diff` based on session scope, bonsai refactoring, and critical file patterns:

```bash
bash install.sh --claude-md          # local
bash install.sh global --claude-md   # global
```

### No dependencies

No Python, npm, or build step required. Just bash and Claude Code.

---

## Usage

```
/critique-diff                     Review staged changes (default)
/critique-diff --diff=all          Review all changes since HEAD
/critique-diff --diff=HEAD~3       Review last 3 commits
/critique-diff --only=risk         Run only the Risk critic
/critique-diff --skip=coverage     Run all critics except Coverage
/critique-diff --severity=red      Report only blockers
/critique-diff --target=src/auth.py  Scope to one file
```

---

## When the hook fires

The `enforce-temper.sh` PreToolUse hook speaks up on the following operations and asks you to run `/critique-diff` first:

| Operation | Condition |
|-----------|-----------|
| `git push` | Always (except `--dry-run`) |
| `git commit` | Staged diff > 200 lines or > 10 files, or critical path file matched |
| `git merge` | Merging into main / master / develop / trunk |
| `git rebase -i` | Range touches > 5 commits |
| `git stash pop` | Stash diff > 200 lines |

None of these stops the command. A `PreToolUse` hook can only do that by exiting 2, and
no aether hook ever does — one corrupt gate file would otherwise lock you out of every
command you type, so the chain is built to fail open and `tests/acceptance.sh` asserts
it. The `git push` and critical-path verdicts are the two the suite never budgets away:
they print in full, alone, and suppress every other plugin's nudge. See
[BYPASS.md](../../BYPASS.md) for the threat model, and the roadmap for the opt-in strict
mode that would let those two exit 2 for real.

**Bypass:** append `# temper:skip`, or `# suite:skip` for every suite hook at once. The
marker is only honoured in a **trailing comment** — after a `#` that starts a word,
outside quotes:

```bash
git push origin main  # temper:skip
git push origin main  # suite:skip
git commit -m "docs: mention # temper:skip"   # NOT a bypass — it is inside the message
```

---

## Reviewing a PR

`/critique-diff` reviews what you are about to commit. `/critique-pr` reviews what
someone is about to merge — the whole PR diff, its CI and mergeable state, and one
critic that only makes sense for a PR: whether the description still matches the code.

```bash
/critique-pr              # the PR for the current branch
/critique-pr --pr=42      # a specific PR
/critique-pr --only=risk  # same flags as /critique-diff
```

It reuses the four critic definitions from `critique-diff.md` rather than restating
them, so the two can never drift. Requires `gh`, authenticated.

## Configuration

One sectioned file per scope — `~/.aether/config` globally, `.aether/config` in a
project — resolved **per key**, so a repo that sets one threshold keeps the global value
of every other. `/draft-config` writes it for you.

```
[temper]
critics:          correctness, design, risk, coverage
severity:         red, yellow
diff:             staged
auto_nudge_lines: 200
auto_nudge_files: 10
critical_paths:   *auth*|*permission*|*token*|migrations/|*alembic*|\.sql|*schema*|*secret*|*credential*|\.env
```

`critical_paths` is **pipe-separated**. A space- or comma-separated list is read as one
pattern and silently matches nothing.

What makes the critics measure rather than guess is the `[project]` section — your real
test, lint and typecheck commands — and it is [ignored until you run `aether
trust`](../../README.md#trust), because a critic executes it.

Prose for the critics goes in `.aether/rules.md`, under `[critique-diff]` or
`[critique-pr]`.

```bash
aether config show temper                    # resolved values, and where each came from
aether config explain temper.critical_paths  # one key in full
aether config set temper.auto_nudge_lines 300
aether config set temper.auto_nudge_lines 300 global
```

> Before v1.1 this was `temper.config` and `~/.claude/temper.config`. Those are still
> read when the new file has no value for a key; `aether migrate` folds them in.

### CLI

```
temper status                     Install state and resolved config
temper enable  [local|global]     Enable temper
temper disable [local|global]     Disable temper
temper config                     Show the resolved [temper] section
temper update                     Reinstall temper from the clone
temper uninstall [global] [--claude-md]
```

`temper` is a shim that execs `aether temper …`, so `aether temper status` is the same
command. **Changing a value is `aether config set`**, not `temper config set` — the
plugin shim's `config` only shows.

---

## Two-tier gate model

**Tier 1 — Proactive (CLAUDE.md rules)**
When installed with `--claude-md`, behavioral guidelines teach Claude Code to suggest `/critique-diff` before you even reach a git command — based on session scope, critical file patterns, and bonsai refactoring activity. They fire before a git command exists to inspect, which is their whole value — and like everything else here, they advise rather than stop.

**Tier 2 — Reactive (enforce-temper.sh hook)**
The hook sees the command itself, which is the part a guideline cannot guarantee. It
recognises high-risk git operations and says so at the moment they happen. It is louder
than Tier 1, not harder: the command still runs either way.

---

## Severity contract

| Rating | Meaning |
|--------|---------|
| 🔴 Blocker | Do not push. Fix first. |
| 🟡 Significant | Fix before the next session or document the exception in the commit message. |
| 🟢 Minor | Fix when convenient. Worth noting. |

---

## Uninstall

```bash
bash uninstall.sh               # local
bash uninstall.sh global        # global
bash uninstall.sh global --claude-md  # also remove CLAUDE.md section
```

---

## The suite

| Plugin | Purpose | When |
|--------|---------|------|
| [whetstone](../whetstone/) | Critique plans | Before you build |
| [bonsai](../bonsai/) | AST refactoring | While you build |
| **temper** | Critique diffs | After you build |
| [cairn](../cairn/) | Git narration | When you ship |

> **Order does not depend on install order.** There is one `PreToolUse` hook for the whole suite, and `enforce-suite.sh` runs the gates in lifecycle order — whetstone, bonsai, temper, cairn — whatever sequence you installed them in.
