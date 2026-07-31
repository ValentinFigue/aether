# aether

Checkpoints for coding agents. aether makes an agent stop at the four moments a careful colleague would — before implementing, while editing, before committing, before pushing — and gives each one a command that does the checking.


| | |
|---|---|
| [The problem](#the-problem) · [Does it hold up](#does-it-hold-up) · [Quick start](#quick-start) | why, whether to believe it, and getting it running |
| [How it works](#how-it-works) · [Configuration](#configuration) · [Trust](#trust) | the part you touch daily |
| [Monorepos](#monorepos--projectpath) · [`aether check`](#monorepos--projectpath) | one declarative place a repo says how to test itself |
| [Commands](#commands) · [The development workflow](#the-development-workflow) | what to run, and when |
| [CLI reference](#cli-reference) · [Bypass](#bypass) · [Roadmap](#roadmap) | reference |

---

## The problem

Claude Code will write code, commit it, and open a PR without stopping to check
anything — and it is very good at making that look finished. The failure mode is
not bad code. It is that **nothing interrupts at the points where a human would.**

You ask for rate limiting on an API. Same request, both columns:

| | without aether | with aether |
|---|---|---|
| **plan** | — | `/critique-plan` → 🔴 an in-process counter does nothing behind a load balancer |
| **edit** | `sed -i s/RateLimit/Limiter/ *.py` — misses the re-export in `api/__init__.py` | bonsai: *use `pyrename`, sed misses re-exports* |
| **commit** | `"add rate limiting"` | `/critique-diff` → 🔴 the limit is never released when the handler raises |
| **push** | pushed, unreviewed | the review you skipped, named — in full, and on its own |
| **PR body** | `"add rate limiting"` | `/draft-pr` writes it from the diff, so it names the Redis dependency you added |

Left column: you find out in review, three days later, or in production. Right
column: at the point where fixing it is a sentence, not a revert.

Each checkpoint is a slash command you can run yourself, plus a hook that reminds
you when you forget.

**Everything the hook does is advice.** It prints; the command then runs. Pushing
unreviewed code and committing to a path you marked critical are the two verdicts that
print in full and alone — nothing else shares the output with them — but they do not
stop the command, and `# aether:skip` silences the rest for one call. A `PreToolUse`
hook can only stop a tool call by exiting 2, and aether never does: one corrupt gate
file would otherwise lock you out of every command you type. See
[Bypass](#bypass) for the threat model, and the roadmap for the opt-in strict mode
that would trade that safety for real teeth.

### Does it hold up

A tool that tells you to check your work should be checkable. **710 assertions across
10 files, plus an acceptance layer** that covers what a unit test cannot: nine hostile
hook payloads where none may exit 2 or write to stderr, `--dry-run` leaving `$HOME`
byte-identical, four consecutive installs producing identical state, and an upgrade from
the previous release with no dangling hooks. The hook's cost is measured against that
release rather than an absolute budget, so a loaded machine cannot raise a false alarm.

It runs on itself. [This repo's own `.aether/config`](.aether/config) extends
`critical_paths` with `hooks/|bin/aether`, because a two-line change there has a blast
radius unrelated to its size — which is the argument the tool makes, applied to the tool.
[Tests](#tests) has the detail.

---

## What it installs

| Plugin | Stage | What it does |
|---|---|---|
| [whetstone](plugins/whetstone/) | Plan | Gates commits when a plan exists but hasn't been critiqued with `/critique-plan` |
| [bonsai](plugins/bonsai/) | Build | Nudges toward AST tools (pyrename, tsmove, pyfindrefs) instead of sed/grep/mv on source files |
| [temper](plugins/temper/) | Review | Calls out large or critical-path commits and unreviewed pushes, unbudgeted and on their own; `/critique-pr` reviews a whole PR before merge |
| [cairn](plugins/cairn/) | Ship | Nudges toward `/draft-commit`, `/draft-pr`, and `/draft-changelog` at every git boundary; `/draft-pr --apply` pushes the description to the PR |
| [trellis](plugins/trellis/) | Setup | `/draft-config` surveys the repo and writes the config the other four read. No hook, no gate — it runs when you ask |

And underneath all five, the part that is useful with no gates installed at all:
**[one declarative place where a repo says how to test, lint, typecheck and build
itself](#configuration)** — per toolchain in a monorepo, with per-key provenance, behind
a direnv-style content-hash [trust boundary](#trust). `aether check` is the single point
that runs any of it, which is what lets the critics *measure* instead of guess.

---

## Quick start

```bash
git clone https://github.com/ValentinFigue/aether && cd aether
bash install.sh --global --claude-md
```

Then once per repository — trellis reads your CI workflows and git history and
writes the config the critics use:

```bash
cd ~/your-project
/draft-config     # writes .aether/config: your test command, lint, git conventions
aether trust      # review what it found, then let the critics run it
```

That is the whole setup. The hooks now nudge at each checkpoint, and the commands
are there when you want them: `/critique-plan`, `/critique-diff`, `/draft-commit`,
`/draft-pr`.

```bash
bash install.sh                       # this project only
bash install.sh --global --no-bonsai  # skip the one plugin needing uv/node/npm
bash install.sh --global --dry-run    # print every step, change nothing
```

**Keep the clone.** bonsai registers its MCP servers by absolute path into it, so
moving or deleting the clone breaks them — re-run `install.sh` from the new location.

Needs `bash` and one of `python3`/`node`/`jq`; bonsai also needs `uv`, `node` and
`npm`, and is skipped with an explanation if they are missing. There is no
`curl | bash` — the installer copies files out of the clone, so piping it could
never have worked.

---

## How it works

Three moving parts, and each has one job.

### 1. A manifest per plugin — what it ships

`plugins/<name>/aether.plugin` declares everything a plugin puts on your machine:
its slash commands, its hooks, its CLI, its skills, its MCP servers, the
permissions it needs, its CLAUDE.md block, and its config schema.

```
name: cairn
scopes: local global
commands: draft-commit.md draft-pr.md draft-changelog.md draft-summary.md
legacy_commands: cairn-commit.md cairn-pr.md ...
hook.1: PreToolUse  | Bash              | hooks/enforce-cairn.sh | suite_owned
hook.2: PostToolUse | Bash\|Write\|Edit | hooks/post-cairn.sh
cli: cairn
permissions: Bash Read Write

config.style.default: conventional
config.style.doc:     Commit format — Conventional Commits, or a plain subject
config.style.used_by: /draft-commit
```

The format is `key: value`, not JSON, deliberately: bash parses it with no
interpreter, so a machine without python3, node or jq still gets its commands,
CLI and templates installed. Only the `settings.json` steps need one.

### 2. The engine — how it gets installed

`bin/aether` reads those manifests and performs five operations: copy a file,
copy a tree, symlink, upsert a JSON key, splice a sentinel block. Two escape
hatches cover the rest — `build` for bonsai's `uv`/`npm` step, and `link` for
the assets it points at the clone instead of copying.

**Uninstall is the same engine reading the same manifest in reverse.** That is
the point of the design: install and uninstall cannot disagree, because there is
only one description of what exists.

`install.sh` and every `plugins/*/install.sh` are one-line wrappers around it.

### 3. The suite hook — how the gates run

`enforce-suite.sh` is a dispatcher with no rules of its own. It sources each
plugin's gate from `gates/` and calls the `gate_<plugin>` function it defines,
so a rule lives in exactly one file whether the plugin runs standalone or under
the suite.

It also sources `aether-config.sh`, the single config parser, which the CLI
shares. There were six independent parsers of the same format before it, and two
of the four plugin copies were missing `head -1` — so a duplicated key resolved
to a multi-line value in half the suite.

```
manifests  ──▶  bin/aether (engine)  ──▶  ~/.claude/commands/
                     │                    ~/.claude/settings.json
                     │                    ~/.claude.json  (MCP)
                     └──────────────────▶ <root>/hooks/enforce-suite.sh
                                          <root>/hooks/gates/enforce-*.sh
                                          <root>/hooks/aether-config.sh
```

### Adding a plugin

Write a manifest and put the assets beside it. There is no installer to write —
`aether install <name>` and `aether uninstall <name>` work from the manifest
alone, and the plugin appears in `aether status` because it exists.

[trellis](plugins/trellis/) is the proof: a manifest and one command file, with
no `install.sh` and no `uninstall.sh`. If the engine needed one, trellis could
not be installed at all, which is asserted in the test suite.

---

## What changes in your environment

Two directories, and the split between them is the rule: **`.claude/` is what
Claude Code reads; `.aether/` is what aether owns.** Both scopes have the same
shape — `~/.aether/` globally, `.aether/` in a project.

```
<root>/config       your settings, one [section] per plugin
<root>/rules.md     prose for the critics
<root>/hooks/       enforce-suite.sh · gates/ · aether-config.sh
<root>/out/         CRITIQUE.md · TEMPER.md
<root>/manifest     what the installer put here
```

In `.claude/`, which belongs to Claude Code: one `PreToolUse` entry in
`settings.json` (matcher `Bash\|Write\|Edit\|MultiEdit\|ExitPlanMode`, the union of
every `suite_owned` matcher the manifests declare), the permissions each
installed plugin declares, the slash commands, and the CLAUDE.md block with
`--claude-md`. bonsai's MCP servers go in `~/.claude.json`. The `aether` binary
goes in `~/.local/bin/`. `$AETHER_HOME` overrides the global root.

`settings.json` and `CLAUDE.md` are copied to `.bak` before the first change.
Per-plugin `PreToolUse` hooks are removed on install, since `enforce-suite.sh`
supersedes them — but `PostToolUse` hooks are not, because the suite hook has no
equivalent for them.

### Upgrading from 1.0.0

`aether install` migrates on the way past: four `<plugin>.config` files per scope
become one sectioned `config`, `whetstone.config.md` and any `pr.rules_file` become
`rules.md`, and `.claude/plans/{CRITIQUE,TEMPER}.md` move to `out/`. Every old file
is copied to `.bak`, the pass is idempotent, and where both exist the **new** value
wins. `aether migrate` runs it alone. Until you migrate the old files are still
*read* when the new one has no value for a key.

---

## Configuration

One file per scope, sectioned, plain text. `~/.aether/config` globally,
`.aether/config` in a project — `/draft-config` writes it for you.

```
enabled: true

[project]            # things to RUN — this is what makes the critics measure
test:      uv run pytest
lint:      uvx ruff check
typecheck: npx tsc --noEmit

[git]                # things to WRITE — house rules for commits and PRs
scopes: api, web, infra
ticket: TK-[0-9]+

[temper]
auto_nudge_lines: 200
critical_paths:   *auth*|*token*|migrations/|*.sql     # pipe-separated

[cairn]
style: conventional
```

Keys outside a section are suite-wide. Sections named after a plugin hold its
settings. The two that describe the repository split on a clear line: **`[project]`
is things to run, `[git]` is things to write.**

| `[project]` | effect |
|---|---|
| `test` | Coverage runs your suite and quotes real failures instead of reading the diff |
| `lint` · `format` · `typecheck` | Correctness reports actual violations with file and line |
| `build` | `/critique-pr` confirms the branch still builds |
| `coverage` · `coverage_min` | Coverage compares a number against a threshold |

| `[git]` | example | effect |
|---|---|---|
| `scopes` · `types` | `api, web` | `/draft-commit` picks from your real ones instead of inventing |
| `ticket` | `TK-[0-9]+` | pulled from the branch into the subject; `/critique-pr` flags a PR without one |
| `trailers` | `Signed-off-by` | always emitted |
| `base` | `main` | `/draft-pr` stops auto-detecting |

### How the layers override

Global, then project, then flags — resolved **per key**, so a project that sets one
threshold keeps the global value of every other:

```
global   [temper] auto_nudge_lines: 200      resolved  auto_nudge_lines: 400  (project)
                  severity: red, yellow                severity: red, yellow  (global)
project  [temper] auto_nudge_lines: 400
```

### Knowing what to change

The schema lives in each plugin's manifest, so a key is documented by being
declared — and `aether config show` answers "if I change this, what happens?":

```
$ aether config show temper
[temper]
  auto_nudge_lines     400            project · .aether/config:14
      Nudge before a commit whose staged diff exceeds this many lines
      used by: enforce-temper.sh
  severity             red, yellow    global · ~/.aether/config:6
```

`aether config doctor` catches what hand-editing produces — a typo is otherwise
silently ignored, the default applies, and the setting appears to do nothing:

```
$ aether config doctor
  ✗ [temper] auto_nudge_line — unknown key  (.aether/config:14)
      did you mean auto_nudge_lines?
  ! [project] lint: git ls-files | xargs shellcheck
      not on PATH: shellcheck — that step will be skipped
```

It checks every command position, not just the first word: `git ls-files | xargs
shellcheck` starts with `git`, so checking one word would report nothing while
shellcheck was silently skipped.

Anything that writes a config emits the doc line as a comment above each key, so
the file explains itself. [This repo's own `.aether/config`](.aether/config) is the
worked example — every value records where it came from, and two keys are
deliberately *unset* with a note on why the obvious value would be wrong.

### Plans and their critiques

`/critique-plan` records its findings **inside the plan**, behind a marker holding a
hash of the plan with that block removed:

```markdown
<!-- aether:critique sha=3f9a1c… date=2026-07-30 blockers=0 -->
## Critique
…
<!-- /aether:critique -->
```

The plan file is the only thing writable in plan mode, so it is the only place a
critique made there can go — and a per-plan record means critiquing one plan no longer
satisfies the gate for every other. Re-saving a plan keeps its critique valid; adding a
section does not.

```
$ aether plan status
  plan:   ~/.claude/plans/rate-limiting.md
  ! the plan changed after its last critique   fix: /critique-plan
```

whetstone nudges when you present the plan, on the first source write, and at
`git commit` — once per uncritiqued plan, not once per project. Leaving plan mode is
the one place it is structurally incapable of interfering: that branch prints and
returns 0 unconditionally.

### Monorepos — `[project:<path>]`

`[project]` assumes one test command for one tree. A monorepo has several, so it gets
one area per toolchain, named for the directory its commands run in:

```
[project:backend]
test:             uv run --frozen pytest
lint:             uv run --frozen ruff check ./
typecheck:        uv run --frozen mypy ./
check.lockfile:   uv lock --check          # a real CI check that fits no standard key

[project:web]
lint:             bun run lint-ci
typecheck:        bun run tsc             # no `test` key — web has no test script
```

Files map to areas by **longest matching path prefix**, the way a CI paths filter
does, so a diff touching only `web/` never runs backend's pytest:

```
$ aether check web/src/App.tsx backend/src/api.py
  project:backend    test        ✓   41s
  project:web        lint        ✓   2s
  project:web        typecheck   ✗   bun run tsc
        src/App.tsx(14,3): error TS2345: …
  project:canvas_processor  not touched — skipped
```

`aether check` is the **only** thing that runs these commands — `/critique-diff` and
`/critique-pr` call it rather than running them themselves, so trust has one
enforcement point. It defaults to files changed against the base branch; `--all` runs
every area, `--raw` is the machine-readable form the critics parse.

**Command keys are not inherited from `[project]`.** A command written for the repo
root has no correct meaning inside a subdirectory, so each area states its own.
Non-command keys like `coverage_min` do inherit. Which is which comes from the
schema — anything declared `type: command`.

Already installed aether inside a subfolder to get this? `aether migrate` folds it in:
`backend/.aether/` becomes `[project:backend]`, only within the same git work tree, and
where a non-`[project]` key differs it keeps the parent's and tells you. The old
directory is left at `backend/.aether.bak`.

### Trust

A project's config can set thresholds the moment you clone it; none of that can
execute anything. Two things can, and both wait for you:

| | why it waits |
|---|---|
| `[project]` commands | a critic would execute them |
| `rules.md` prose | it reaches a critic's context — an injection vector with no log |

Until you trust a project those two are ignored, global config and prose are used
instead, and **the critic says so in its report**. `aether trust` prints the
commands and the prose *before* recording anything:

```
$ aether trust
Trusting /Users/you/Code/thing
  Commands the critics would run:
    test        uv run pytest
  Prose that would reach a critic (.aether/rules.md, 4 line(s)):
    [critique-diff]
    We use event sourcing — flag anything that bypasses the event log.
```

Trust is a content hash, so **hand-editing either file asks again** — loudly,
rather than silently falling back to global. `aether config set` re-hashes
automatically, because you made the change through the tool. That asymmetry is
direnv's model and the reason it is safe. Global config and prose are always
trusted: you wrote them.

### `rules.md` — prose for the critics

Free text beside the config, one section per command. Prose **concatenates**
global-then-project rather than overriding — losing your global writing rules
because a repo added a line would be the wrong default.

```markdown
[all]
This is a bash project. Prefer POSIX-compatible constructs.

[critique-diff]
We use event sourcing — flag anything that bypasses the event log.
```

---

## Commands

Eight slash commands. Every one reads its defaults from config, and every one
takes flags that override config for that run.

### Plan — whetstone

```bash
/critique-plan                      # three critics: impl, arch, risk
/critique-plan --only=impl,arch     # just those two
/critique-plan --skip=risk          # all defaults except one
/critique-plan --severity=red       # only blockers
/critique-plan --off                # skip it this once
```

Four more critics are opt-in because they are not always relevant: `testing`,
`complexity`, `api`, `cost`. Ask for them by name — `/critique-plan --only=impl,api`.

The findings are written **into the plan**, behind an `aether:critique` marker — the
only file plan mode lets anything write, and the record the gate reads
([Plans and their critiques](#plans-and-their-critiques)). The same report is also
appended to `.aether/out/CRITIQUE.md` with a date header, which accumulates a history
across plans. A 🔴 means don't start implementing yet.

### Build — bonsai

bonsai has no slash command. It is 13 MCP tools plus a gate that notices when you
reach for `sed` on a `.py` file:

```
python (8)      pyrename · pymove · pymovesymbol · pysignature
                pyfindrefs · pycallers · pyfindunused · pygrep
typescript (5)  tsrename · tsmove · tsmovesymbol · tssignature · tsfindrefs
```

Ask for the operation and Claude picks the tool: *"rename `parse_config` to
`load_config` everywhere"* uses `pyrename`, which follows re-exports and aliased
imports that a text replace silently misses. Always dry-run a mutating tool first.

### Review — temper

```bash
/critique-diff                      # five critics over the staged diff
/critique-diff --diff=all           # staged + unstaged
/critique-diff --target=src/auth.py # one file
/critique-diff --only=correctness,risk
/critique-diff --severity=red,yellow

/critique-pr                        # the PR for the current branch
/critique-pr --pr=42
/critique-pr --severity=red         # blockers only, before merging
```

The five critics are Correctness, Design, Risk, Coverage and Documentation — the last
asking whether any sentence describing a behaviour this diff changes is still true.
`/critique-pr` adds a sixth that only makes sense for a PR: whether the description
still matches the code. An *omitted* change is weighted above an inaccurate one — a reviewer who
trusts the description will not go looking for what it does not name.

With `[project]` set and the repo trusted, Correctness and Coverage run your real
tooling and quote real failures. Without it they read the diff and say so.

### Ship — cairn

```bash
/draft-commit                       # message from the staged diff
/draft-commit --style=plain         # no Conventional Commits prefix
/draft-commit --raw                 # just the message, nothing else

/draft-pr                           # title + description from the branch diff
/draft-pr --apply                   # …and push it to the PR with `gh pr edit`
/draft-pr --apply --title           # also replace the title (opt-in)
/draft-pr --base=develop --pr=42

/draft-changelog --version=1.2.0    # entry from the last tag to HEAD
/draft-changelog --from=v1.0.0 --to=HEAD

/draft-summary                      # standup notes from the last day
/draft-summary --format=slack --from=v1.0.0
/draft-summary --format=paragraph --author=you@example.com
```

`--apply` is the one that writes to something outside your checkout. Everything
else prints and lets you paste.

### Setup — trellis

```bash
/draft-config                       # detect, ask about gaps, write .aether/config
/draft-config --global              # write ~/.aether/config instead
/draft-config --dry-run             # print what it would write
/draft-config --only=project,git    # just those sections
/draft-config --force               # overwrite keys you already set
```

Run this once per repo. It never runs what it detects — `aether trust` is a
separate, explicit step.

---

## The development workflow

One pass through a change, and where each command earns its place.

### 1. Set the repo up — once

```bash
cd ~/Code/my-project
/draft-config            # writes .aether/config from CI, manifests, git history
aether config show       # read it back: values, sources, what each key does
aether trust             # review the commands, then allow the critics to run them
git add .aether/config .aether/rules.md && git commit -m "chore: add aether config"
```

Committing `.aether/config` is the point — it is a description of the project, so
your colleagues get the same thresholds and the same test command. `out/` and
`manifest` are per-developer and should stay ignored.

### 2. Plan, before writing anything

Describe the change; Claude proposes a plan in `.claude/plans/<name>.md`. Then:

```bash
/critique-plan
```

🔴 findings mean the plan is wrong, not the code. Fixing a plan costs a
conversation; fixing the same problem after implementation costs a refactor.
whetstone's gate enforces this at `git commit`: a plan on disk with no critique
newer than it produces a nudge.

### 3. Build

Nothing to invoke. Ask for the change you want. Two things happen on their own:

- Reach for `sed`/`grep`/`mv` on a `.py`, `.ts`, `.tsx`, `.js` or `.jsx` file and
  bonsai's gate points at the AST tool that handles re-exports and aliased imports.
- After a rename-shaped edit, `post-bonsai.sh` re-checks references and says if
  something now dangles.

### 4. Review, before it leaves your machine

```bash
git add -p
/critique-diff           # Coverage runs your test command; Correctness runs lint and typecheck
```

Fix the 🔴s. 🟡 either gets fixed or written down. temper's gate speaks up on a
`git push` that has had no review, and on a commit touching a critical path — auth,
migrations, secrets, schemas — regardless of size. Those two are the only messages that
never share the output with another plugin. They do not stop the command.

### 5. Ship

```bash
/draft-commit            # reads the diff, not your memory of it
git commit -m "<paste>"
/draft-pr --apply        # opens or updates the PR description
```

Then, once the PR is open and CI has gone green — which is exactly when nobody
re-reads it:

```bash
/critique-pr             # the same five critics over the whole PR, plus description accuracy
```

Commits landed after the description was written? Then the description is the most
likely thing in the PR to be wrong, and that fifth critic is the one that matters.

### 6. Release

```bash
/draft-changelog --version=1.2.0
/draft-summary --format=slack --from=v1.1.0
```

### Bypassing, when the discipline is wrong

The gates are advice, not policy. One marker turns any of them off for one command:

```bash
git commit -m "wip"           # aether:skip
git push origin main          # temper:skip
grep -r TODO ./src            # bonsai:skip
```

### How the gates actually run

```
git commit / git push / Write source file / leaving plan mode
         │
         ▼
  enforce-suite.sh          ← dispatcher only; no rules of its own
         │
         ├── sources gates/enforce-whetstone.sh  → gate_whetstone
         ├── sources gates/enforce-bonsai.sh     → gate_bonsai
         ├── sources gates/enforce-temper.sh     → gate_temper
         └── sources gates/enforce-cairn.sh      → gate_cairn
         │
    ┌────┴──────────────────┬──────────────────────┐
    │                       │                      │
    ▼                       ▼                      ▼
 Bash tool        Write / Edit / MultiEdit    ExitPlanMode
    │                       │                      │
    ├─ gate_whetstone       └─ gate_whetstone      └─ gate_whetstone
    │  (plan exists,           (first source          (presenting an
    │   no critique?)           write, no              uncritiqued plan?
    │                           critique?)             prints, never gates)
    │
    ├─ gate_bonsai
    │  (text tools on source files?)
    │
    ├─ gate_temper
    │  (large diff? critical path? push?)
    │
    └─ gate_cairn
       (weak commit message? push?)
```

Each gate is defined once, in its own plugin's `hooks/enforce-<plugin>.sh`, and runs either standalone or sourced by the suite.

`enforce-suite.sh` skips any plugin whose config says `enabled: false`, and any gate that is not installed.

Every gate is advisory: the hook exits 0 or 1 and the tool call proceeds either way. Only
exit 2 stops a call in Claude Code, and nothing here uses it — a gate that is corrupt or
half-written would then lock you out of every command, so the whole chain is built to
fail open and `tests/acceptance.sh` asserts no payload can make it exit 2. temper's two
high-risk verdicts (push without review, critical-path commit) are *unbudgeted* rather
than blocking: they print in full, alone, and suppress everything else.

**One nudge per tool call.** Gates run top to bottom, but their output does not
accumulate: the hook prints the earliest stage with something to say and names the rest
on one line. A `git commit` that tripped whetstone, temper and cairn used to print
fifteen lines from three plugins, and nudge fatigue is how guardrails die — the fastest
way to stop the noise becomes `# aether:skip` on everything.

```
Whetstone: a plan exists but has not been critiqued yet.
  .claude/plans/p.md
  Run /critique-plan before committing to surface blockers now.
  Append  # whetstone:skip  to your git command to bypass.
  + temper and cairn also had notes — `aether status --notes` to see them.
```

temper's two high-risk verdicts are exempt from the budget: each prints in full and
alone, and the nudges beside it are dropped rather than appended. Being told your push
had no review is the only thing worth reading at that moment. Whatever was held back
goes to `.aether/out/.notes`, overwritten each call.

**One interpreter per tool call.** The hook used to start three python3 processes on a
`git commit` — its own stdin parse plus temper's and cairn's rules — at roughly 18ms
each, on a path that runs on every Bash, Write and Edit of every session. There is now
a single parse in `aether_parse_command`, and every rule is bash, git and awk.
`tests/test_hookcost.sh` counts the interpreters rather than timing them, so a loaded
CI machine cannot produce a false alarm.

---

## CLI reference

```
aether install [plugin...] [global] [--claude-md] [--no-bonsai] [--dry-run]
aether uninstall [plugin...] [global] [--claude-md]
aether status                            Plugin state, gates, clone, version
aether status --notes                    Nudges the hook's budget held back
aether doctor [--fix] [--deep]           Check the install against the manifests
aether docs                              Check the docs against the code and config
aether config show [section] [--values|--raw]
aether config explain <section>.<key>
aether config doctor                     Just the config and trust half
aether config set|unset <section>.<key> [value] [global]
aether config path|edit [global]
aether check [path...] [--all] [--raw]   Run this project's [project] commands
aether project for <file...>             Which monorepo areas those files touch
aether plan [status|path|hash]           The plan the gate sees, and its critique state
aether trust [status|list|forget|prune]
aether rules                             The prose the critics will read
aether migrate                           Move a pre-1.0 layout into ~/.aether/
aether enable|disable [local|global]      All plugins
aether hook enable|disable <plugin>       Stop a gate loading at all
aether update                             git pull the clone, re-run the installer
aether version · aether help
```

Every plugin answers to its own name — `aether cairn status` — and the `cairn`,
`temper`, `whetstone` and `bonsai` binaries are 24-line shims that exec exactly
that, so there is one implementation.

A plugin's `config` subcommand takes the same verbs as `aether config` and resolves the
section from the schema, so you do not have to know which one a key lives in — including
the keys cairn declares under `[git]`:

```
cairn config set trailers Signed-off-by     ≡  aether config set git.trailers Signed-off-by
temper config set auto_nudge_lines 300      ≡  aether config set temper.auto_nudge_lines 300
```

`enable`/`disable` writes `enabled: false` for the gate to read; `hook
enable`/`disable` stops the gate being loaded. The soft mute is usually what you
want.

```
$ aether status
aether v1.5.0

  bonsai       enabled  MCP: bonsai-py bonsai-ts
  whetstone    enabled
  temper       enabled
  cairn        enabled
  trellis      enabled

  Suite hook: enforce-suite.sh registered (global)
  Gates:      4 loaded from /Users/you/.aether/hooks/gates
  Clone:      /Users/you/Code/aether
  Installed version: 1.5.0
```

### `aether doctor`

`status` says what is installed; `doctor` says what is wrong with it. Every check
compares the state on disk against what the manifests declare, and every finding
names its fix.

```
$ aether doctor
install (global)
  ✗ PostToolUse: ~/.local/share/cairn/post-cairn.sh is registered but does not exist
      Claude Code tries to run it on every matching tool call
      fix: aether doctor --fix
  ✗ post-cairn.sh is registered more than once — it fires once per registration
  ! 2 command(s) from a pre-1.0 install are still in the palette
  ✓ 14 manifest entries all present on disk
  ✓ permissions match what the installed plugins declare
  ✓ 4 gates parse
config
  ✗ [temper] auto_nudge_line — unknown key  (.aether/config:14)
trust
  ! 1 entry(ies) point at a directory that no longer exists
      fix: aether trust prune

3 problem(s), 2 warning(s).
```

It exists because every bug that mattered in 1.1.0 shared a shape: **the tool
reported success and had done nothing.** The engine registered no MCP servers for
six commits. An upgrade left a hook pointing into a deleted directory.
`post-cairn.sh` fired twice. All invisible from outside — in a tool whose job is
noticing problems.

`--fix` performs only the three repairs where the right action is unambiguous:
deregister a hook whose script is gone, drop a duplicate registration, prune dead
trust entries. Everything else prints the command. `--deep` also handshakes each
MCP server, which spawns `uv` and `node`.

### `aether docs`

`doctor` checks the install; `docs` checks what your documentation *claims*. Every defect
in the 1.5.0 documentation audit was found by hand, and most of them were mechanically
detectable — this is the mechanism, and it works in any repository, not just this one.

```
$ aether docs
README.md
  ✗ README.md:230  [temper] critical_paths is pipe-separated; this example is
                   space-separated and matches nothing
      fix: join the patterns with |
  ! README.md:88   [project] test runs this as `uv run --frozen pytest`
      the doc omits the wrapper, so following it skips what the wrapper does

1 problem(s), 1 warning(s) across 7 file(s).
```

Four families, in rough order of what they are worth:

| | |
|---|---|
| **Prose contradicting `[project]`** | Your config already declares how the repo really runs. A README saying `pytest` where the config says `uv run --frozen pytest` is what a new joiner follows on day one. Per area, so a monorepo command that is right for `web/` and wrong for `backend/` is caught |
| **Commands that do not exist** | `npm run X` with no such script, `make Y` with no such target, `bash scripts/z.sh` that moved |
| **Dead references** | Relative links, and `](#anchor)` against the headings actually in the file |
| **aether's own claims** | Config keys and values against the manifest schema, subcommands and flags against the engine, retired paths outside a migration note |

Deliberately narrow: **nothing is inferred.** Every check compares a documented string
against a declared or on-disk fact, because a checker that reports plausible-but-wrong
findings gets switched off within a week. Judgement — *is this sentence still true after
my change?* — belongs to the Documentation critic in `/critique-diff`.

Scope it with `[docs]`, and wire it into review with one line:

```
[docs]
paths:  README.md docs/ plugins/*/README.md    # default: *.md at the root, plus docs/
ignore: CHANGELOG.md                           # a changelog is meant to describe old behaviour

[project]
check.docs: aether docs
```

`aether check` runs any `check.<name>` key, and `/critique-diff` and `/critique-pr` call
`aether check` — so that one line puts the check in front of every review. It exits
non-zero on problems, so CI can use it too.

`[project]` commands are ignored until you run `aether trust`; without it the first
family cannot run, and `aether docs` says so rather than quietly checking less.

---

## Bypass

Full specification: [BYPASS.md](BYPASS.md)

| Marker | Effect |
|---|---|
| `# aether:skip` | Silence all gates |
| `# suite:skip` | Alias for aether:skip |
| `# whetstone:skip` | Silence whetstone gate only |
| `# bonsai:skip` | Silence bonsai gate only |
| `# temper:skip` | Silence temper gate only |
| `# cairn:skip` | Silence cairn gate only |

```bash
git push origin main          # aether:skip
git commit -m "wip"           # temper:skip cairn:skip
grep -r "TODO" ./src          # bonsai:skip
```

A marker only counts in a **trailing comment** — after a `#` that starts a word, outside
quotes, with nothing but further markers behind it. Until v1.5.0 each gate grepped for
its own marker anywhere in the command, so a commit *documenting* one silenced the suite:

```bash
git commit -m "docs: explain the # aether:skip marker"    # ran every gate; used to run none
```

---

## Installing plugins individually

You can install one plugin instead of all five. Each plugin's installer lives beside it:

```bash
aether install cairn global --claude-md
aether install temper whetstone global
bash plugins/cairn/install.sh global              # equivalent; a wrapper
```

**"Standalone" means one plugin's assets, not a machine without aether.** Every install
goes through the same engine, so it also lays down the `aether` CLI, `enforce-suite.sh`
and the shared `aether-config.sh` — the way an MCP server needs a host. The suite hook
is always the one registered; a plugin never registers a `PreToolUse` hook of its own,
because its manifest marks that hook `suite_owned` and the engine installs in suite mode
on every path. `--claude-md` is what controls whether the CLAUDE.md block is written.

What *is* standalone is the gate. Each one is a `gate_<plugin>` function in its own
file, so the same rule runs whether `enforce-suite.sh` sources it or the file is
executed directly — which is what the dual-mode equivalence tests assert.

---

## Tests

Two layers. The unit suite asserts behaviour; the acceptance script exercises the
things that only appear in a real install.

```bash
bash tests/run.sh                  # 710 assertions across 10 files, ~3 min
bash tests/run.sh doctor           # one file
bash tests/run.sh config           # the config, trust and migration tests
bash tests/run.sh hookcost         # interpreter count, bypass precision, the budget
bash tests/run.sh rules            # what each gate's rule decides, case by case

bash tests/acceptance.sh           # end to end against a throwaway HOME, ~4 min
bash tests/acceptance.sh --full     # also build bonsai and handshake its MCP servers
bash tests/acceptance.sh --perf-only  # just what the hook costs per tool call
```

`acceptance.sh` covers what a unit test cannot: a path with spaces, nine hostile
hook inputs (none may exit 2, which would block the tool call, and none may write to
stderr), `--dry-run` leaving the home directory byte-identical with bonsai included,
four consecutive installs producing identical state, upgrading from the last release
with no dangling hooks, `aether doctor` clean both before and after that upgrade, and
the hook's per-tool-call cost measured **against that release** rather than an
absolute budget — so a loaded machine does not raise a false alarm. It never touches
your real `$HOME`.

Plain bash and python3, no packages. The unit suite covers dual-mode gate
equivalence (each gate behaves identically standalone and under the dispatcher),
bypass markers, fail-open on malformed input, per-key config resolution, trust,
migration, install idempotence, and uninstall.

---

## Roadmap

Deliberately short, and ordered by what is actually in the way. Everything here is a gap
someone has hit, not a feature idea.

**Five people, one week.** Nobody outside this repo has run the suite on a repository
they care about. Every item below is a guess until they have, and their week would
reorder this list more reliably than any amount of reasoning about which command to
build next. It is first because it is the cheapest way to find out that the rest is
wrong.

**A distribution story.** Today it is `git clone` plus a script, and the clone has to
stay put forever because bonsai's MCP servers reference it by absolute path — move it
and they break. A published package fixes that. A plugin marketplace entry was
previously written off as premature, which is backwards: at zero stars the constraint is
not that the tool is unready, it is that nobody can find it, and the marketplace is where
Claude Code users look.

**Strict mode.** Nothing here stops a command today, because a `PreToolUse` hook can only
do that by exiting 2 and one corrupt gate file would then lock you out of everything. An
opt-in `strict: true` would let temper's two high-risk verdicts exit 2 for real, and stop
honouring a bypass marker on them. Worth being precise about what that buys: the agent
could still edit the config, deregister the hook, or route around the matcher. It raises
the cost of a bypass from *appending a comment* — invisible and deniable — to *editing a
tracked file*, which shows up in a diff. It is not a boundary. A pre-receive hook or a
required CI check is a boundary, and [BYPASS.md](BYPASS.md) says so.

**One trigger surface.** whetstone, temper and cairn all fire on the same event, and
v1.5.0 needed a lifecycle-ordered budget to stop them talking over each other. That
budget is the evidence: three plugins expressing one idea — *stop before git* — through
three CLAUDE.md sentinels, three config sections and three gate files. Not a decision to
merge them; the budget is the experiment, and once it has been lived with either the
separation earns its keep or it collapses into one gate with three critics.

**Close the loop between review and fix.** A critic finds something and a human retypes
it. `/critique-diff --fix` applying only the mechanical findings — the ones with a file,
a line and one obvious edit — would remove the retyping without removing the judgement.

**Work with any agent, not just Claude Code.** The checking is already portable:
bonsai's tools are plain MCP, the config and prose are plain text, the CLI is bash,
and the commands are markdown prompts. What is Claude Code specific is the automatic
interruption — the gates register in its `settings.json` and parse its PreToolUse
payload. Each rule already lives in one file behind a `gate_<plugin>` function, so
another host is payload translation rather than a rewrite. The intent is to support
Cursor, Windsurf, Zed and anything else that grows an equivalent hook.

**Merge discipline.** `aether merge` gating on the things worth blocking a merge
for — critique run, description accurate, CI green on the actual head — rather
than leaving them to whoever remembers.

**Dependencies.** Nothing in the suite looks at what a change pulls in.
`/critique-deps` for a new or bumped dependency: is it maintained, does it need
network at runtime, does the licence fit.

**Decisions.** `/draft-adr` from a critiqued plan. The plan already contains the
alternatives and why they were rejected, which is the expensive half of an ADR,
and it is currently thrown away once the code lands.

---

## Uninstall

```bash
# Remove suite hook, gates and CLI (plugins remain installed)
bash uninstall.sh --global

# Also remove the CLAUDE.md block
bash uninstall.sh --global --claude-md
```

Or via the CLI: `aether uninstall global --claude-md`

The four plugins stay installed and usable on their own; their slash commands and `PostToolUse` hooks are left in place. Remove them with `plugins/<name>/uninstall.sh`.

---

## License

MIT
