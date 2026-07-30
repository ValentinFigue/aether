# aether

Checkpoints for Claude Code. aether makes a coding agent stop at the four moments a careful colleague would — before implementing, while editing, before committing, before pushing — and gives each one a command that does the checking.


| | |
|---|---|
| [The problem](#the-problem) · [Quick start](#quick-start) | why, and getting it running |
| [How it works](#how-it-works) · [Configuration](#configuration) · [Trust](#trust) | the part you touch daily |
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
| **push** | pushed, unreviewed | blocked until it has been reviewed |
| **PR body** | `"add rate limiting"` | `/draft-pr` writes it from the diff, so it names the Redis dependency you added |

Left column: you find out in review, three days later, or in production. Right
column: at the point where fixing it is a sentence, not a revert.

Each checkpoint is a slash command you can run yourself, plus a hook that reminds
you when you forget. Nothing blocks except pushing unreviewed code and committing
to a path you marked critical — everything else is a nudge, and
`# aether:skip` silences any of it for one command.

### Why one suite rather than four plugins

The four started as separate Claude Code plugins, and each installed its
own hook, its own bypass syntax, and edited `settings.json` on its own. Install all
four and you get four competing hook registrations, four redundant checks on the
same `git commit`, and no way to turn them all off at once.

aether is the wiring: one `PreToolUse` hook that knows the order of things, one
`settings.json` pass, one config file, one bypass convention, one CLAUDE.md block.
The plugins still install and run standalone — this is coordination, not a rewrite.

---

## What it installs

| Plugin | Stage | What it does |
|---|---|---|
| [whetstone](plugins/whetstone/) | Plan | Gates commits when a plan exists but hasn't been critiqued with `/critique-plan` |
| [bonsai](plugins/bonsai/) | Build | Nudges toward AST tools (pyrename, tsmove, pyfindrefs) instead of sed/grep/mv on source files |
| [temper](plugins/temper/) | Review | Blocks large/critical commits and pushes until `/critique-diff` has been run; `/critique-pr` reviews a whole PR before merge |
| [cairn](plugins/cairn/) | Ship | Nudges toward `/draft-commit`, `/draft-pr`, and `/draft-changelog` at every git boundary; `/draft-pr --apply` pushes the description to the PR |
| [trellis](plugins/trellis/) | Setup | `/draft-config` surveys the repo and writes the config the other four read. No hook, no gate — it runs when you ask |

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
`settings.json` (matcher `Bash\|Write\|Edit\|MultiEdit`), the permissions each
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
critical_paths:   *auth* *token* migrations/ *.sql

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
| `trailers` | `Co-Authored-By` | always emitted |
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

Findings are appended to `.aether/out/CRITIQUE.md` with a date header, so the
file accumulates a history rather than being overwritten. A 🔴 means don't start
implementing yet.

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
/critique-diff                      # four critics over the staged diff
/critique-diff --diff=all           # staged + unstaged
/critique-diff --target=src/auth.py # one file
/critique-diff --only=correctness,risk
/critique-diff --severity=red,yellow

/critique-pr                        # the PR for the current branch
/critique-pr --pr=42
/critique-pr --severity=red         # blockers only, before merging
```

The four critics are Correctness, Design, Risk and Coverage. `/critique-pr` adds
a fifth that only makes sense for a PR: whether the description still matches the
code. An *omitted* change is weighted above an inaccurate one — a reviewer who
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

Fix the 🔴s. 🟡 either gets fixed or written down. temper's gate blocks a `git push`
that has had no review, and blocks a commit touching a critical path — auth,
migrations, secrets, schemas — regardless of size.

### 5. Ship

```bash
/draft-commit            # reads the diff, not your memory of it
git commit -m "<paste>"
/draft-pr --apply        # opens or updates the PR description
```

Then, once the PR is open and CI has gone green — which is exactly when nobody
re-reads it:

```bash
/critique-pr             # the same four critics over the whole PR, plus description accuracy
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
git commit / git push / Write source file
         │
         ▼
  enforce-suite.sh          ← dispatcher only; no rules of its own
         │
         ├── sources gates/enforce-whetstone.sh  → gate_whetstone
         ├── sources gates/enforce-bonsai.sh     → gate_bonsai
         ├── sources gates/enforce-temper.sh     → gate_temper
         └── sources gates/enforce-cairn.sh      → gate_cairn
         │
    ┌────┴────────────────────────────────────────┐
    │                                             │
    ▼                                             ▼
 Bash tool                              Write / Edit / MultiEdit
    │                                             │
    ├─ gate_whetstone                             └─ gate_whetstone
    │  (plan exists, no critique?)                   (first source write, no critique?)
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

Each gate is defined once, in its own plugin's `hooks/enforce-<plugin>.sh`, and runs either standalone or sourced by the suite. Gates run top to bottom and their messages accumulate, so a single `git push` can surface both a temper and a cairn nudge.

`enforce-suite.sh` skips any plugin whose config says `enabled: false`, and any gate that is not installed. All gates are non-blocking nudges, except temper which blocks high-risk operations (push without review, critical-path commit).

---

## CLI reference

```
aether install [plugin...] [global] [--claude-md] [--no-bonsai] [--dry-run]
aether uninstall [plugin...] [global] [--claude-md]
aether status                            Plugin state, gates, clone, version
aether doctor [--fix] [--deep]           Check the install against the manifests
aether config show [section] [--values|--raw]
aether config explain <section>.<key>
aether config doctor                     Just the config and trust half
aether config set|unset <section>.<key> [value] [global]
aether config path|edit [global]
aether check [path...] [--all] [--raw]   Run this project's [project] commands
aether project for <file...>             Which monorepo areas those files touch
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

`enable`/`disable` writes `enabled: false` for the gate to read; `hook
enable`/`disable` stops the gate being loaded. The soft mute is usually what you
want.

```
$ aether status
aether v1.2.0

  bonsai       enabled  MCP: bonsai-py bonsai-ts
  whetstone    enabled
  temper       enabled
  cairn        enabled
  trellis      enabled

  Suite hook: enforce-suite.sh registered (global)
  Gates:      4 loaded from /Users/you/.aether/hooks/gates
  Clone:      /Users/you/Code/aether
  Installed version: 1.2.0
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

---

## Installing plugins individually

Standalone installs remain fully supported — aether is optional coordination, not a requirement for any single plugin. Each plugin's installer lives beside it:

```bash
aether install cairn global --claude-md
aether install temper whetstone global
bash plugins/cairn/install.sh global              # equivalent; a wrapper
```

Installing any plugin also installs the `aether` engine, the way an MCP server
needs a host. "Standalone" means only that plugin's assets, not a machine
without aether.

Run without `--suite` (as above) and a plugin registers its own `PreToolUse` hook and its own CLAUDE.md block. The suite installer passes `--suite` to suppress both.

---

## Tests

Two layers. The unit suite asserts behaviour; the acceptance script exercises the
things that only appear in a real install.

```bash
bash tests/run.sh                  # 473 assertions, ~4 min
bash tests/run.sh doctor           # one file
bash tests/run.sh config           # the config, trust and migration tests

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

Deliberately short. Everything here is a gap someone has actually hit, not a
feature idea.

**Close the loop between review and fix.** A critic finds something and a human
retypes it. `/critique-diff --fix` applying only the mechanical findings — the
ones with a file, a line and one obvious edit — would remove the retyping without
removing the judgement.

**Dependencies.** Nothing in the suite looks at what a change pulls in.
`/critique-deps` for a new or bumped dependency: is it maintained, does it need
network at runtime, does the licence fit.

**Decisions.** `/draft-adr` from a critiqued plan. The plan already contains the
alternatives and why they were rejected, which is the expensive half of an ADR,
and it is currently thrown away once the code lands.

**A verify command.** `aether check` running everything in `[project]` in one
pass, so the same commands a critic uses are one keystroke for a human too.

**Merge discipline.** `aether merge` gating on the things worth blocking a merge
for — critique run, description accurate, CI green on the actual head — rather
than leaving them to whoever remembers.

**The plan critique cannot record itself.** Two independent mismatches:
`enforce-whetstone.sh` looks for plans in `.claude/plans/`, but plan mode writes to
`~/.claude/plans/` — so the gate never sees the plan you actually wrote. And the
critique's last step writes `.aether/out/CRITIQUE.md`, which plan mode forbids, so
the automatic critique cannot persist. Fix: glob both directories, and let the
critique live *inside* the plan file — the one file plan mode can write — stamped
with a hash of the plan body so staleness is content-based rather than mtime-based.

**Work with any agent, not just Claude Code.** The checking is already portable:
bonsai's tools are plain MCP, the config and prose are plain text, the CLI is bash,
and the commands are markdown prompts. What is Claude Code specific is the automatic
interruption — the gates register in its `settings.json` and parse its PreToolUse
payload. Each rule already lives in one file behind a `gate_<plugin>` function, so
another host is payload translation rather than a rewrite. The intent is to support
Cursor, Windsurf, Zed and anything else that grows an equivalent hook.

**A distribution story.** Today it is `git clone` plus a script, and the clone has
to stay put because bonsai's MCP servers reference it by absolute path. A
published package would fix that; a plugin marketplace entry was considered and
rejected as premature.

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
