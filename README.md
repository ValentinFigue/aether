# aether

Aether binds bonsai, whetstone, temper, and cairn into a single coordinated suite — one repo, one install, one config, one bypass convention, one hook that knows the order of things. A fifth plugin, trellis, writes the config the other four read.


| | |
|---|---|
| [Install](#install) · [How it works](#how-it-works) | getting it onto a machine |
| [Configuration](#configuration) · [Trust](#trust) | the part you touch daily |
| [Commands](#commands) · [The development workflow](#the-development-workflow) | what to run, and when |
| [CLI reference](#cli-reference) · [Bypass](#bypass) | `aether …`, and turning it off |
| [Roadmap](#roadmap) | what is missing |

---

## Why

Each Claude Code plugin installs its own hook, its own bypass syntax, and touches `settings.json` independently. Install all four and you get four competing hook registrations, redundant gate checks on the same git command, and no shared way to silence them all at once.

Aether solves the wiring problem:

- One `PreToolUse` hook (`enforce-suite.sh`) replaces all four per-plugin hooks
- One `settings.json` pass — no per-plugin editing
- One bypass convention (`# aether:skip`) silences everything; per-plugin markers (`# temper:skip`) work too
- One unified CLAUDE.md block covers all four plugins

Since 1.0.0 all four plugins live in this repository, so setting up a new machine is one `git clone` and one script — no network access during install, and the four can never drift to different versions. The plugins are unchanged in behaviour: each still installs and runs standalone.

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

## Install

```bash
git clone https://github.com/ValentinFigue/aether
cd aether

# Global, with the CLAUDE.md rules block (recommended)
bash install.sh --global --claude-md

# Local (this project only)
bash install.sh

# Skip bonsai — the only plugin needing uv, node and npm
bash install.sh --global --no-bonsai

# Dry run — see what would happen without making changes
bash install.sh --global --dry-run
```

**Keep the clone.** bonsai registers its MCP servers in `~/.claude.json` by absolute path into this directory, so moving or deleting the clone breaks them. Re-run `install.sh` from the new location if you do move it.

### Prerequisites

`bash` and `python3` (or `node`, or `jq`) for everything except bonsai. bonsai additionally needs `uv`, `node` and `npm` to build its Python and TypeScript servers. If those are missing the installer skips bonsai, tells you how to finish later, and installs the rest.

There is no `curl | bash` one-liner. The installer copies files out of the clone, so piping it to bash could never have worked, and dropping it also removes a remote-code-execution path from the install flow.

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
Claude Code reads; `.aether/` is what aether owns.**

Both scopes use the same directory name and the same shape — `~/.aether/`
globally, `.aether/` in a project. Referred to below as `<root>`.

```
<root>/
  config          your settings, one [section] per plugin
  rules.md        prose for the critics, one section per command
  templates/      optional file templates (e.g. pr.md)
  hooks/          enforce-suite.sh · gates/ · aether-config.sh
  out/            CRITIQUE.md · TEMPER.md · .nudged
  manifest        what the installer put on this machine
```

| What | Where |
|---|---|
| Config | `<root>/config` — sectioned, resolved per key |
| Prose rules | `<root>/rules.md` — concatenated, global then project |
| `enforce-suite.sh` | `<root>/hooks/enforce-suite.sh` |
| Plugin gates | `<root>/hooks/gates/enforce-<plugin>.sh` — sourced by the suite hook |
| Plugin hooks | `<root>/hooks/plugin-hooks/` — PostToolUse scripts the suite has no equivalent for |
| Config reader | `<root>/hooks/aether-config.sh` — the one parser, shared with the CLI |
| Generated output | `<root>/out/` — CRITIQUE.md, TEMPER.md |
| Install manifest | `<root>/manifest` |
| Hook registration | `settings.json` — one `PreToolUse` entry, matcher `Bash\|Write\|Edit\|MultiEdit` |
| Permissions | `settings.json` — `Bash`, `Read`, `Write`, plus each installed plugin's own (bonsai adds `mcp__bonsai-*__*`) |
| Slash commands | `~/.claude/commands/` — `critique-*.md`, `draft-*.md` |
| CLAUDE.md block | injected with `--claude-md` flag |
| `aether` CLI | `~/.local/bin/aether` — a binary belongs on PATH |

`$AETHER_HOME` overrides the global root if you would rather it lived at
`~/.config/aether`. One variable, read in one place.

Hook *scripts* live under `<root>/hooks/` because `settings.json` references them
by absolute path, so they can live anywhere. That also retires
`~/.local/share/aether/`, which used to hold the global hook while the local one
sat in `.claude/hooks/` — different parents for the same artefact.

Per-plugin `PreToolUse` hooks are removed during install, since `enforce-suite.sh` supersedes them. `settings.json` and `CLAUDE.md` are copied to `.bak` before the first change.

### Upgrading from 1.0.0

`aether install` migrates the old layout on the way past — four `<plugin>.config`
files per scope become one sectioned `config`, `whetstone.config.md` and any
`pr.rules_file` become `rules.md`, and `.claude/plans/{CRITIQUE,TEMPER}.md` move
to `out/`. Every old file is copied to `.bak` before being removed, the pass is
idempotent, and where both old and new exist the **new** value wins.

`aether migrate` runs it on its own. Until you migrate, the old
`<plugin>.config` files are still *read* when the new file has no value for a
key, so nothing breaks in the meantime.

### PreToolUse is unified; PostToolUse is not

The suite hook covers the `PreToolUse` phase only. cairn and bonsai also register `PostToolUse` hooks — `post-cairn.sh` (suggests `/draft-commit` after a clean review, `/draft-changelog` after a version bump) and `post-bonsai.sh` (reference-drift check after a rename-shaped edit). These have no equivalent in the suite hook, so they are left registered per-plugin rather than removed.

---

## Configuration

One file per scope, sectioned. Plain text — open it and edit it; nothing caches.

```
# ~/.aether/config — your defaults, everywhere
enabled: true

[project]
test:      uv run pytest
lint:      uvx ruff check
typecheck: npx tsc --noEmit

[git]
scopes: api, web, infra
ticket: TK-[0-9]+

[temper]
auto_nudge_lines: 200
critical_paths:   *auth* *token* migrations/ *.sql

[cairn]
style: conventional

[whetstone]
critics: impl, risk
```

Keys outside any section are suite-wide. The four sections named after plugins
carry that plugin's settings, with every key name unchanged from the pre-1.0
`<plugin>.config` files. Two sections describe the repository rather than a
plugin, and they split on a clear line: **`[project]` is things to run,
`[git]` is things to write.**

### `[project]` — commands the critics execute

Shell commands. This is what upgrades Coverage from *inferring* that tests exist
to actually running them — so it needs `aether trust` before it takes effect.
Each critic names the command it ran and its exit status, and says plainly when
it could not run anything rather than implying a check happened.

| Key | What changes if you set it |
|---|---|
| `test` | `/critique-diff` and `/critique-pr` Coverage runs the suite and reports real failures |
| `lint` / `format` | Correctness reports actual violations instead of eyeballing style |
| `typecheck` | Correctness runs it against the changed files |
| `build` | `/critique-pr` can confirm the branch still builds |
| `coverage` / `coverage_min` | Coverage compares against a threshold instead of a judgement call |

### `[git]` — how this project writes commits and PRs

No commands, nothing executed. House rules that `/draft-commit` and `/draft-pr`
follow and `/critique-pr` checks against.

| Key | Example | What changes if you set it |
|---|---|---|
| `scopes` | `api, web, infra` | `/draft-commit` picks from your real scopes instead of inventing one |
| `types` | `feat, fix, docs, chore` | restricts the Conventional Commits type it may use |
| `ticket` | `TK-[0-9]+` | `/draft-commit` pulls the ticket from the branch name into the subject; `/critique-pr` flags a PR with none |
| `trailers` | `Co-Authored-By` | `/draft-commit` always emits them |
| `base` | `main` | `/draft-pr` stops auto-detecting the base branch |

### How the layers override

Three layers, resolved **per key** — not per file, and not per section:

| Layer | Source | Beats |
|---|---|---|
| 1 | `~/.aether/config` | — |
| 2 | `<project>/.aether/config` | global |
| 3 | flags, e.g. `/critique-diff --severity=red` | both |

A project file overrides only the keys it names. Set `severity` globally and
`auto_nudge_lines` in one repo, and both apply:

```
global   [temper] auto_nudge_lines: 200
                  severity: red, yellow
project  [temper] auto_nudge_lines: 400
                                              ↓
resolved [temper] auto_nudge_lines: 400   (project)
                  severity: red, yellow   (global)
```

### Letting trellis write it

`[project]` is the section that upgrades Coverage from inferring to measuring, and
it is also the section nobody fills in — writing five shell commands by hand is
exactly the kind of task that gets postponed.

```bash
/draft-config          # detect, ask about the gaps, write .aether/config
```

trellis looks at **CI workflows first**: a `run:` line in
`.github/workflows/*.yml` is a command that provably works in a clean checkout,
because someone maintains it and it fails loudly when it rots. Manifest scripts
come second and are noisier — this repository's own `package.json` offers
`test:watch`, which a critic must never run. It reads the repo last, for commit
sizes and the git conventions actually in use.

Every key it writes carries a comment naming where the value came from, so a
detected command is distinguishable from a guess. It never overwrites a key you
have set, never selects a watch-mode or deploy script, and never runs what it
detects — that is what `aether trust` is for, and the report says so.

### Knowing what to change

The question a config file has to answer is "if I change this, what happens?"
The schema lives in each plugin's manifest, beside the assets it already
declares, so a key is documented by being declared — and `aether config show`
answers the question inline:

```
$ aether config show temper

[temper]
  auto_nudge_lines     400                    project · .aether/config:14
      Nudge before a commit whose staged diff exceeds this many lines
      used by: enforce-temper.sh
  auto_nudge_files     10                     default
      Same, for number of files changed
      used by: enforce-temper.sh
  severity             red, yellow            global · ~/.aether/config:6
      Which severities get reported
      used by: /critique-diff /critique-pr
```

Value, which layer supplied it, the file and line to edit, what it does, and
what consumes it. `--values` drops the prose once you know the file; `--raw`
emits bare `key: value` lines, which is what the slash commands read.

**aether configures itself.** [`.aether/config`](.aether/config) in this repo is the
worked example — committed, because it describes the project rather than the
developer. Every key records where its value came from, so a detected command is
distinguishable from a guess, and two keys are deliberately *unset* with a note
explaining why the obvious value would be wrong.

`aether config doctor` catches what hand-editing actually produces:

```
$ aether config doctor
  ✗ [temper] auto_nudge_line — unknown key  (.aether/config:14)
      did you mean auto_nudge_lines?
  ! [project] lint: git ls-files '*.sh' | xargs shellcheck
      not on PATH: shellcheck — that step will be skipped
  ✓ 14 key(s) resolved
```

An unknown key is the one worth catching most: a typo is silently ignored, the
default applies, and the setting simply appears to have no effect. The PATH check
looks at every command position, not just the first word — `git ls-files | xargs
shellcheck` starts with `git`, which is always there, so checking one word would
report nothing while shellcheck was silently skipped.

`aether config explain <section>.<key>` prints one key in full — default, type,
every layer that sets it, and which commands read it.

**The file explains itself.** Anything that writes a config — `config set`, or
the installer seeding a first one — emits the doc line as a comment above each
key, so "what can I put here?" is answered by the file you already have open.

```
[temper]
# Nudge before a commit whose staged diff exceeds this many lines
auto_nudge_lines: 400
```

### `rules.md` — prose for the critics

Free text, one section per command, replacing the two mechanisms that existed
before it: whetstone's auto-discovered `whetstone.config.md` and cairn's
`pr.rules_file` pointer.

```markdown
[all]
This is a bash project. Prefer POSIX-compatible constructs.

[critique-diff]
We use event sourcing — flag anything that bypasses the event log.

[draft-pr]
Always mention the ticket ID in the first line.
```

Prose **concatenates** rather than overriding: global first, then project.
That differs from `config` deliberately — losing your global writing rules
because a repo added one line would be the wrong default.

### Trust

A project's config can set thresholds and pick critics the moment you clone it —
none of that can execute anything. Two things can, and both wait for your
consent:

| What | Why it waits |
|---|---|
| `[project]` run-commands | a critic would execute them |
| `rules.md` prose | it reaches a critic's context, which is an injection vector with no log |

Until you trust a project, those two are ignored, global config and global prose
are used instead, and **the critic says so in its report header** — a review with
less context than the file suggests is worse than one with no rules at all.

```bash
aether trust           # show what you are consenting to, then record it
aether trust status    # none | ok | changed
aether trust forget    # revoke
```

`aether trust` prints the commands and the prose *before* recording anything,
because otherwise it is a formality:

```
$ aether trust
Trusting /Users/you/Code/thing

  Commands the critics would run:
    test        uv run pytest
    typecheck   npx tsc --noEmit

  Prose that would reach a critic (.aether/rules.md, 4 line(s)):
    [critique-diff]
    We use event sourcing — flag anything that bypasses the event log.
```

Trust is a content hash, so **hand-editing either file asks again** — loudly,
rather than silently falling back to global, which would hide that anything
changed. Edits made through `aether config set` re-hash automatically, because
you made them through the tool. This is direnv's model and the reason it is safe.

Global config and global prose are always trusted: you wrote them.

### Editing by hand

```bash
aether config path [global]                     # print the file path
aether config edit [global]                     # open it in $EDITOR
aether config show [<section>]                  # resolved values + what each does
aether config explain temper.auto_nudge_lines   # one key, in full
aether config doctor                            # validate
aether config set   temper.auto_nudge_lines 400 [global]
aether config unset temper.auto_nudge_lines
```

`config set` rewrites only the line it targets, preserving your comments and
ordering, and creates the section if it is missing.

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
                                         Install the suite, or just the named plugins
aether uninstall [plugin...] [global] [--claude-md]
                                         Remove a plugin, or the suite layer itself
aether status                            Plugin state, gates, clone path, version
aether config show [section] [--values|--raw]
                                         Resolved values, where each came from
aether config explain <section>.<key>    One key in full
aether config doctor                     Validate: unknown keys, dead paths
aether config set|unset <section>.<key> [value] [global]
aether config path|edit [global]         Print or open the config file
aether trust [status|forget]             Allow this project's [project] commands
                                         and rules.md to be used
aether rules                             Print the prose the critics will read
aether migrate                           Move a pre-1.0 layout into ~/.aether/
aether enable  [local|global]            Enable all plugins
aether disable [local|global]            Disable all plugins
aether hook enable|disable <plugin>      Stop a gate being invoked at all
aether update                            git pull the clone and re-run the installer
aether version                           Print the CLI and installed versions
aether help                              Show help
```

Every plugin also answers to its own name — `aether cairn status` — and the
`cairn`, `temper`, `whetstone` and `bonsai` binaries are 24-line shims that exec
exactly that, so `cairn status` still works and there is one implementation.

`enable`/`disable` and `hook enable`/`disable` are different: the first writes
`enabled: false` for the gate to read, the second stops the gate being loaded.
The soft mute is usually what you want; the hard one is for debugging.

### Worked examples

```bash
# What is installed, and where
aether status
aether config path                       # ./.aether/config
aether config path global                # ~/.aether/config

# Read the config, three ways
aether config show                       # everything, with docs and sources
aether config show temper --values       # values and sources, no prose
aether config show temper --raw          # bare `key: value`, what the commands read
aether config explain cairn.pr.base      # one key: default, type, every layer

# Change it
aether config set temper.auto_nudge_lines 400          # this project
aether config set cairn.style plain global             # everywhere
aether config unset temper.auto_nudge_lines
aether config edit global                              # open it in $EDITOR

# Check it
aether config doctor                     # unknown keys, missing binaries, trust state

# Allow this project's commands and prose to be used
aether trust
aether trust status                      # none | ok | changed
aether trust forget

# Turn things off
aether disable                           # all plugins, this project
aether disable global                    # all plugins, everywhere
aether config set bonsai.enabled false   # one plugin, this project
aether hook disable bonsai               # stop the gate loading at all (debugging)

# Maintain
aether update                            # git pull the clone, re-run the installer
aether migrate                           # move a pre-1.0 layout into ~/.aether/
aether install temper global             # add one plugin
aether uninstall bonsai global           # remove one plugin
```

**Example output of `aether status`:**

```
aether v1.0.0

  bonsai       enabled  MCP: bonsai-py bonsai-ts
  whetstone    enabled
  temper       enabled
  cairn        enabled
  trellis      enabled

  Suite hook: enforce-suite.sh registered (global)
  Gates:      4 loaded from /Users/you/.aether/hooks/gates
  Clone:      /Users/you/Code/aether
  Installed version: 1.0.0
```

**A worked config, end to end:**

```bash
$ cd ~/Code/my-api
$ /draft-config
Wrote .aether/config

  [project]
    test        uv run pytest      from .github/workflows/ci.yml
    lint        uvx ruff check     from .github/workflows/ci.yml
    typecheck   mypy src           guessed from pyproject.toml — verify this
  [git]
    scopes      api, web, infra    from 200 commits (81% conventional)

  Skipped 1 candidate:
    npm run test:watch             watch mode

Nothing runs yet. Review the commands, then: aether trust

$ aether config show project --values
[project]
  test        uv run pytest      project · .aether/config:4
  lint        uvx ruff check     project · .aether/config:6
  typecheck   mypy src           project · .aether/config:8

$ aether config get project.test          # withheld: not trusted yet

$ aether trust
  Commands the critics would run:
    test        uv run pytest
    lint        uvx ruff check
    typecheck   mypy src
  ✓ trusted.

$ aether config get project.test
uv run pytest
```

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
bash tests/run.sh                  # 420 assertions, ~3 min
bash tests/run.sh gates            # one file
bash tests/run.sh config           # the config, trust and migration tests

bash tests/acceptance.sh           # end to end against a throwaway HOME, ~4 min
bash tests/acceptance.sh --full     # also build bonsai and handshake its MCP servers
bash tests/acceptance.sh --perf-only  # just what the hook costs per tool call
```

`acceptance.sh` covers what a unit test cannot: installing into a path with
spaces, nine hostile hook inputs (none may exit 2, which would block the tool
call, and none may write to stderr), `--dry-run` leaving the home directory
byte-identical with bonsai included, four consecutive installs producing identical
state, upgrading from the last release with no dangling hooks, and the per-tool-call
cost of the hook measured **against that release** rather than an absolute budget,
so a loaded machine does not produce a false alarm. It never touches your real
`$HOME`.

Plain bash and python3, no packages to install. The suite covers dual-mode gate equivalence (each gate behaves identically standalone and under the dispatcher), bypass markers, fail-open on malformed input, install idempotence, migration from a standalone install, and uninstall.

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

**Multi-repo config.** `[project]` assumes one test command for one tree. A
monorepo needs per-path sections, and that is a real design question rather than
a small change.

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
