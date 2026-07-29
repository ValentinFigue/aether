# Changelog

All notable changes to aether are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

From 1.0.0 the four plugins live in this repository and share its version
number. Their individual histories are preserved under
[Pre-consolidation history](#pre-consolidation-history).

## [Unreleased]

### Added

- **One sectioned config file per scope.** `~/.aether/config` and
  `.aether/config` replace four `<plugin>.config` files per scope, with an
  `[<section>]` per plugin and every key name unchanged. Resolution stays
  **per key**, so a project that sets one key does not discard the global value
  of its neighbours.
- **Two new sections that describe the repository rather than a plugin**, split
  on a clear line — `[project]` is things to run (`test`, `lint`, `typecheck`,
  `build`, `coverage`), `[git]` is things to write (`scopes`, `types`, `ticket`,
  `trailers`, `base`). Both are declared in the manifest of the plugin that
  consumes them, so there is no suite-wide schema file to install.
- **`.aether/rules.md`** — prose for the critics, one section per command,
  replacing whetstone's auto-discovered `whetstone.config.md` and cairn's
  `pr.rules_file` pointer. Prose *concatenates* global-then-project rather than
  overriding: losing your global writing rules because a repo added one line
  would be the wrong default.
- **`aether config`** — `show`, `explain`, `doctor`, `path`, `edit`, `get`,
  `set`, `unset`. `show` prints each value with the layer, file and line that
  supplied it, what the key does, and which command reads it. `doctor` catches
  unknown keys with a suggestion, and `[project]` commands whose binary is not
  on `PATH`. `--raw` emits bare `key: value` lines, which is what the slash
  commands now read instead of merging two files themselves.
- **`aether migrate`**, also run automatically by `aether install`. Idempotent,
  and where both old and new exist the **new** value wins. Every old file is
  copied to `.bak` before removal.
- **`hooks/aether-config.sh`** — one config parser, sourced by both the CLI and
  every gate. There were six independent readers of this format; two of the four
  plugin copies were missing `head -1`, so a duplicated key resolved to a
  multi-line value in half the suite.
- **Trust, on direnv's model.** `~/.aether/trusted` maps a project path to a
  content hash of its `config` plus `rules.md`. Until a project is trusted its
  `[project]` run-commands and its `rules.md` are ignored — the two things in a
  repo that can act on your machine, one by being executed and one by reaching a
  critic's context. Everything else in a project's config applies immediately.
  `aether trust` prints the commands and the prose before recording anything.
  Hand-editing either file asks again, loudly, rather than silently downgrading
  to global; `aether config set` re-hashes automatically.
- **Critics that measure instead of infer.** `/critique-diff` gains a measurement
  pass that runs the configured `typecheck`, `lint`, `test` and `coverage`, and
  Correctness and Coverage start from that output. Each names the command it ran
  and its exit status, and says plainly when nothing was configured.
  `/critique-pr` stops treating `gh pr checks` as a proxy for having verified
  anything — an empty check list is not a passing one — and runs `build` itself
  when the branch is checked out.
- **trellis** — a fifth plugin, and the proof that adding one now needs a
  manifest and assets: it ships no `install.sh` and no `uninstall.sh`, so if the
  engine needed one it could not be installed at all. Asserted in the tests.
  Its one command, `/draft-config`, surveys the repo and writes the config the
  other four read — CI workflows first, because a `run:` line provably works in
  a clean checkout, then manifests, then the repo itself for commit sizes and
  the git conventions actually in use. Every key carries a comment naming its
  source, existing values are never overwritten, and watch-mode, server and
  deploy scripts are never selected — a watch script would hang a critic
  indefinitely. It writes commands but never runs them, and says so.
- `aether rules` — prints the prose the critics will read, global then project,
  with its own trust state stated in the output.
- `tests/test_config.sh` — 70 assertions on per-key merge, schema completeness,
  `doctor`, comment-preserving writes, pre-migration fallback, and migration
  including its idempotence.

### Changed

- **`~/.aether/` and `.aether/` are now the roots**, with the same name and the
  same shape in both scopes. `.claude/` holds what Claude Code itself reads
  (commands, `settings.json`, skills, `CLAUDE.md`, plan mode's `plans/`);
  `.aether/` holds what aether owns. `$AETHER_HOME` overrides the global root.
- **`~/.local/share/aether/` is retired.** It held the global hook while the
  local one sat in `.claude/hooks/` — different parents for the same artefact.
  Hook scripts move to `<root>/hooks/`, which `settings.json` can reference by
  absolute path from anywhere.
- Generated output moves to `<root>/out/`: `CRITIQUE.md`, `TEMPER.md`, and
  whetstone's nudge sentinel. Plan files stay in `.claude/plans/`, which is plan
  mode's own directory.
- The install manifest moves from `~/.claude/aether.manifest` to
  `<root>/manifest`.
- `aether enable`/`disable` write one sectioned file instead of four.
- Two tests stopped hardcoding the four plugin names — the palette check now
  derives a command's owning plugin from its path, and the enable/disable checks
  count the manifests. Adding a plugin should not fail a test about something
  else.

### Fixed

- **`aether enable` and `aether disable` wrote the verb, not the value.**
  Collapsing the two into one variable during the refactor produced
  `enabled: disable`, which is not `false` — so nothing was disabled and
  `aether status` still reported every plugin as on. Caught by the existing
  suite.
- **whetstone's once-per-project nudge briefly became once-per-machine.** The
  sentinel moved to `.aether/out/` and was resolved through the same helper as
  `CRITIQUE.md`, which falls back to `~/.aether/out/` for a project with no
  `.aether/` — so the first project to be nudged silenced every other one. It is
  now pinned to the project, with a test for exactly that.
- Migration no longer copies a *global* `pr.rules_file` into every project it
  touches: `[draft-pr]` prose is imported from the scope that set it.
- `_mf` matched manifest keys by regex, so `config.pr.base.doc` could match a
  line where the dots were any character. Now a literal prefix match.
- **`--dry-run` ran bonsai's build for real** — `uv sync` and `npm run build`,
  writing to `~/.cache` and `~/.npm`. The five primitives are guarded centrally,
  but `build` is the one escape hatch that runs arbitrary commands and was never
  covered. `--dry-run` also created `~/.claude.json` via the MCP sync, and left
  empty `.aether/hooks/gates/` directories behind. It is now verifiably inert,
  with a test asserting the *whole* home directory is byte-identical afterwards.
- The gate count printed after install used `ls`; it now uses a glob, so the
  message is right on a machine stripped down to bash and coreutils.
- `aether uninstall` left `aether-config.sh` orphaned in the hook directory.
- **The jq backend errored on a `settings.json` with no `hooks` key** —
  `with_entries` on null is an error, not a no-op — so a jq-only user with a
  permissions-only settings.json got `null (null) has no keys` on stderr and the
  stale-hook cleanup silently did not happen. All three backends now produce
  byte-identical output, and a phase aether does not manage (`SessionStart`) is
  preserved.
- **`printf: write error: Broken pipe` on Linux.** `_schema_all | awk '… exit'`
  closed the pipe while the writer was still going. macOS dies from SIGPIPE
  silently, so it passed locally and failed on CI; the tests capture with `2>&1`,
  so the message became part of the value and four assertions broke. Both readers
  now consume their input, and eleven assertions check directly that no
  subcommand writes to stderr.
- **A relocated hook was registered twice.** cairn used to install standalone into
  `~/.local/share/cairn/`, and a machine that had done that ran `post-cairn.sh`
  twice on every Bash, Write and Edit. Registration now deduplicates on the
  script's basename, which covers every past and future location without keeping
  a list of them.
- **`--dry-run` printed `✓ … registered` for work it had not done.** The same
  failure as the earlier dry-run bugs, one level up in the output. Completed steps
  now route through one helper that marks them `· … — not applied` under
  `--dry-run`, asserted by a test that forbids a `✓` in dry-run output entirely.
- **bonsai's MCP servers were never registered by the engine.** The spec was
  piped to `python3 -`, which reads its *program* from stdin — so the heredoc
  carrying the program claimed stdin, `sys.stdin.read()` returned nothing, and
  the engine wrote an empty `mcpServers: {}` and reported success. The spec now
  travels via argv. A server whose command cannot be resolved is refused outright
  rather than written with an empty `command`, which Claude Code would try to
  launch. `AETHER_REPO` was added so the engine can be exercised without a real
  install, which is what makes this testable.
- **Trust now fails closed with no SHA-256 available.** The first version fell
  back to `cksum`, which is CRC32 — cheap enough to collide that someone able to
  change a trusted repo's config could keep the checksum and keep the trust.
  `openssl dgst` was added as a third option, and where none exists the project
  reads as untrusted and says why. Losing the feature is the right trade against
  losing the guarantee.

### Documentation

- README gains **Commands** (every slash command with the flags that override
  config), **The development workflow** (one pass through a change, from
  `/draft-config` to `/draft-changelog`), worked `aether` CLI examples including a
  config walked end to end, and a short **Roadmap**. A table of contents, because
  it is now long enough to need one.

### Notes

Until you migrate, the pre-1.0 `<plugin>.config` files in either scope are still
*read* when the new file has no value for a key. Writes only ever go to the new
location, so the two cannot diverge.

## [1.0.0] — 2026-07-28

bonsai, cairn, whetstone and temper now live in this repository. One clone, one
version, one installer, no network access at install time.

### Added

- `plugins/` — bonsai, cairn, whetstone and temper imported with full git
  history via `git subtree`
- `--suite` flag on all four plugin installers: installs commands, CLI and
  PostToolUse hook, but skips the PreToolUse hook and the plugin's own
  CLAUDE.md block, both superseded by the suite
- **`/critique-pr`** — reviews an open PR before merge, completing the triad the command
  rename established: plan → diff → PR. It applies temper's existing four critics rather
  than a new checklist, reading their definitions out of `critique-diff.md` in the same
  commands directory so the two cannot drift, and adds a fifth that only makes sense for
  a PR: whether the description still matches the diff. An unmentioned change is weighted
  above an inaccurate one — a reviewer who trusts the description will not look for what
  it does not name. Also reports CI and mergeable state up front, since a red build is
  worth knowing before reading a code review
- **`/draft-pr --apply`** — pushes the generated description to the PR with `gh pr edit`
  instead of only printing it for pasting. `--title` additionally sets the title
  (opt-in, since titles are often hand-edited after opening) and `--pr=<n>` targets a
  specific PR. With no PR for the branch it prints the `gh pr create` command rather than
  creating one
- `--no-bonsai` flag on `install.sh` for a shell-only install
- `aether version` subcommand
- `tests/` — 203 assertions run by `bash tests/run.sh`, covering dual-mode gate
  equivalence, bypass markers, fail-open behaviour (including corrupt, truncated
  and empty gate files), JSON-backend equivalence across python3/node/jq,
  install idempotence, migration from a standalone install, and uninstall.
  Plain bash, no dependencies, so it runs anywhere the suite does
- `AETHER_JSON_BACKEND` — pins the interpreter that rewrites `settings.json`, so
  the node and jq fallbacks can be tested rather than only ever running on
  machines without python3
- `.github/workflows/tests.yml` — CI for the suite
- Install manifest records `repo=`, `gates=`, `claude_md=`, `bonsai=` and
  `plugins=`
- `aether status` reports the loaded gate count and the clone path

### Changed

- **Every slash command is renamed to one act-and-object vocabulary.** The six
  commands shipped under three conventions — `/autocritic` (bare verb, no owner),
  `/temper` (bare plugin name, no verb) and `/cairn-*` (`<plugin>-<verb>`) — which
  hid what the suite is: two commands critique something that exists, four draft
  text you are about to write. Naming them after the implementing plugin also
  listed the pipeline backwards in the alphabetically-sorted palette.

  | Was | Now |
  |---|---|
  | `/autocritic` | `/critique-plan` |
  | `/temper` | `/critique-diff` |
  | `/cairn-commit` | `/draft-commit` |
  | `/cairn-pr` | `/draft-pr` |
  | `/cairn-changelog` | `/draft-changelog` |
  | `/cairn-summary` | `/draft-summary` |

  Plugin names, CLI binaries, `# <plugin>:skip` markers and `<plugin>.config`
  filenames are unchanged. Each command's first line now names its owning plugin,
  so the palette description says which plugin to `disable`. Upgrading removes the
  old command files automatically — see *Fixed*.
- **bonsai is installed automatically.** It was previously skipped with a FIXME
  telling you to clone it yourself. Its installer already resolved its own root
  from `BASH_SOURCE` and registered MCP servers by absolute path, so sharing
  this clone was all it ever needed. Missing `uv`/`node`/`npm` degrades to a
  skip with instructions rather than failing the suite
- **No network at install time.** cairn and whetstone fetched their commands,
  CLIs and hooks from `raw.githubusercontent.com`; everything now resolves from
  the clone. This also removes a `curl | bash` pipeline from the install path
- **`hooks/enforce-suite.sh` is a dispatcher, not a rulebook** — 467 lines down
  to 155. It carried its own copy of all four gates, so every rule existed
  twice; it now sources each plugin's hook with `SUITE_MODE=1` and calls the
  `gate_<plugin>` function it defines
- Each plugin hook is dual-mode: one gate function, invoked either by its own
  standalone entrypoint or by the suite
- `aether update` is a `git pull --ff-only` plus a re-run of the local
  installer, preserving the recorded scope and flags
- `uninstall.sh` is a wrapper around `aether uninstall`; the two had been
  near-verbatim duplicates and only one knew about the gates directory
- All versions unified to 1.0.0, and per-plugin CHANGELOGs merged into this file
- bonsai's CI workflow hoisted to the repo root with a `plugins/bonsai/**` path
  filter — GitHub only runs workflows at the root

### Fixed

- **The suite deleted PostToolUse hooks it did not replace.** The stale-hook
  sweep removed `post-cairn` and `post-bonsai`, but `enforce-suite.sh` is
  PreToolUse-only. Installing aether silently disabled bonsai's
  reference-drift nudge and cairn's post-review and changelog nudges. The sweep
  now touches PreToolUse only
- **`enforce-cairn.sh` had never worked.** Its message-extraction regex wrote
  apostrophes as `\'` inside a heredoc nested in `$( )`. Bash tracks quote state
  through the body while scanning for the closing paren, so an odd number of
  single quotes broke the substitution and every commit and push printed
  `syntax error near unexpected token )` instead of the nudge. None of cairn's
  three nudges had ever displayed. Release 0.3.1 attributed this to CRLF line
  endings, which was not the cause. Writing apostrophes as `\x27` balances the
  body
- **MCP permissions matched nothing.** Eight files wrote `mcp__bonsai_py__*`
  with underscores, but the servers register as `bonsai-py`, so the tools are
  named `mcp__bonsai-py__*`. Two hook matchers were affected too, which is why
  the dry-run confirmation prompt on mutating refactors never fired. Installers
  also strip the old spelling from existing configs
- **The `/temper` slash command was missing from the temper repo.** Its
  `.gitignore` used the bare pattern `TEMPER.md`, which git matches at any depth
  and case-insensitively on macOS, silently swallowing
  `.claude/commands/temper.md`. Anyone who cloned temper got an installer that
  failed. Patterns are now anchored
- The advertised `curl … install.sh | bash` one-liner could never work — the
  script copies `hooks/` and `bin/` relative to itself, neither of which exists
  when piped to bash. Removed in favour of clone-then-run
- Plugin installs reported success unconditionally; a total failure still
  printed a green tick. Failures are now named and exit non-zero
- `_json_remove_stale_hooks` was python3-only while its two siblings had node
  and jq fallbacks; without python3 it silently did nothing
- `settings.json` and `CLAUDE.md` are backed up before the first mutation —
  every JSON helper rewrites via `> tmp && mv`, which truncates on a partial write
- whetstone emitted `<!-- whetstone:start -->` twice, wrapping a template that
  already carried its own sentinels
- temper wrote its gate's python to a `mktemp` file on every Bash tool call to
  work around the heredoc bug above; its body is quote-balanced, so it is
  inlined and nothing touches `/tmp`
- **Nothing pruned superseded command files, and the CLAUDE.md block was frozen.**
  Two problems the command rename exposed. No install path ever removed a
  `commands/*.md` it no longer shipped, so a rename would leave orphans in the
  palette still invoking stale copies; the manifest now records `commands=` and
  each install prunes what it recorded but no longer ships, backing up any file
  the user had edited. And CLAUDE.md injection *skipped* whenever the aether
  block already existed, freezing the injected rules at whatever version first
  wrote them — after the rename it would have kept telling Claude to run commands
  that no longer exist. Injection now replaces the block, so it tracks the
  template for this and every future change
- **`cairn update`, `temper update` and `whetstone update` fetched from the
  pre-monorepo repos.** They re-downloaded command files by name from
  `raw.githubusercontent.com/ValentinFigue/<plugin>`. Those repos are archived
  but still serve content, so after the rename they would have written the old
  files back under the old names and undone the prune. All three now re-run the
  local installer from the clone recorded in the aether manifest
- **`cairn`/`temper`/`whetstone` `update` ignored the recorded scope** — a second
  instance of the same bug as `aether uninstall` below. All three ran
  `install.sh global` regardless of `scope=`, so updating a local install silently wrote
  a global one into `~/.claude`. Scope is now read alongside `repo=` and passed through
- **The command prune could abort an install midway.** Its `cp`/`rm` ran unguarded under
  `set -e`, after the plugins were installed but before the hook, gates, permissions and
  manifest were written, so one unremovable file left a half-configured machine with no
  explanation. Failures now warn and continue — a surviving orphan is the lesser problem
- **`aether uninstall` ignored its scope argument.** The hook, gates, CLI and
  manifest paths were hardcoded to the global locations, so a local uninstall
  removed none of what a local install had created — leaving
  `.claude/hooks/enforce-suite.sh`, `.claude/hooks/gates/` and `.bin/aether`
  behind — while deleting the *global* manifest and with it the `repo=` entry
  `aether update` needs to find the clone. Every path is now derived from the
  scope, preferring what the manifest recorded, and empty directories the
  install created are tidied away

### Removed

- The `curl | bash` install one-liner and the four standalone plugin `curl`
  commands
- Per-plugin `CHANGELOG.md` files, merged below
- `gate_whetstone_write` — whetstone's own gate already branches on the tool name

---

## Pre-consolidation history

Each plugin's changelog as it stood when it was merged into this repository.

### aether

#### [0.1.0] — 2026-05-07

- `install.sh` — suite installer; registers `enforce-suite.sh` as the single PreToolUse hook and installs bonsai, whetstone, temper, and cairn
- `uninstall.sh` — clean removal of the suite hook, CLI, and optional CLAUDE.md block
- `hooks/enforce-suite.sh` — central dispatch hook; replaces per-plugin hooks with a single coordinated gate chain
- `bin/aether` — CLI for `status`, `update`, `enable`, `disable`, `uninstall`, and `help`
- `templates/CLAUDE.md` — unified CLAUDE.md block under `<!-- aether:start -->` / `<!-- aether:end -->` sentinels
- `BYPASS.md` — canonical bypass specification

### bonsai

#### [0.2.0] — 2026-05-07

**Added**
- `hooks/post-bonsai.sh` — PostToolUse hook (matcher: `Write|Edit|MultiEdit`): nudges to verify reference integrity after edits that look like renames or signature changes
- `# suite:skip` bypass marker accepted alongside `# bonsai:skip`
- "Works well with" suite table in README

**Changed**
- `hooks/enforce-bonsai.sh` expanded: intercepts `rg`, `ripgrep`, `ag`, `ack`, `perl`, `xargs` chains, and `mv`/`git mv`/`cp` on source files; nudges are operation-specific (search / mutate / move)
- Source extension coverage extended to `.js`, `.jsx`, `.mjs`
- `templates/CLAUDE.md` rewritten with proactive triggers and a "when NOT to use bonsai" section
- `install.sh` registers both PreToolUse and PostToolUse hooks

#### [0.1.0] — 2026-05-06

**Changed**
- Bash nudge hook switched from `prompt` type (LLM-evaluated, over-blocked `git` and `gh`) to a deterministic `command` script
- Hook is advisory only (exit 1 = warn but allow)

**Added**
- `hooks/enforce-bonsai.sh`; `# bonsai:skip` bypass marker
- `bonsai enable-hook` auto-migrates an installed `prompt` hook to the `command` type

#### [0.0.2] — 2026-05-06

- `install.sh` / `uninstall.sh` with optional `--claude-md`
- `bin/bonsai` CLI: `install`, `uninstall`, `status`, `enable-hook`, `disable-hook`, `update`
- `--published` flag to switch MCP registration to `uvx` / `npx`
- `templates/CLAUDE.md`, `templates/bash_nudge_prompt.txt`

#### [0.0.1] — 2026-05-05

**bonsai-py** — AST-based Python refactoring MCP server: `pyrename`, `pymove`, `pymovesymbol`, `pysignature`, `pyfindrefs`, `pycallers`, `pyfindunused`, `pygrep`.

**bonsai-ts** — TypeScript/TSX refactoring MCP server: `tsrename`, `tsmove`, `tsmovesymbol`, `tssignature`, `tsfindrefs`.

All mutating tools default to `dry_run=True`.

### cairn

#### [0.3.1] — 2026-05-07

**Fixed**
- `hooks/enforce-cairn.sh` and `hooks/post-cairn.sh`: replaced `cat <<'MSG'` heredocs with `printf`, attributed at the time to CRLF line endings. See the 1.0.0 Fixed section — the actual cause was an odd number of single quotes in a heredoc nested inside `$( )`, and `enforce-cairn.sh` remained broken until 1.0.0

#### [0.2.0] — 2026-05-06

**Added**
- `/cairn-pr`, `/cairn-changelog`, `/cairn-summary` commands
- `hooks/enforce-cairn.sh` PreToolUse hook with `# cairn:skip` bypass

**Changed**
- `/cairn` renamed `/cairn-commit`; all commands follow `cairn-<verb>`
- Commands read `enabled:` and `style:` from `cairn.config` at runtime
- `bin/cairn` `update`/`status`/`uninstall`/`config` cover all four command files

#### [0.1.0] — 2026-05-06

- `/cairn` command: Conventional Commits message from the staged diff
- `--style=conventional` / `--style=plain`
- Secrets detection (`sk-`, `AKIA`, `ghp_`, `ghs_`, `-----BEGIN`)
- Multi-group detection suggesting separate commits
- `bin/cairn` CLI and `cairn.config`

### temper

#### [0.1.1] — 2026-05-07

**Added**
- `# suite:skip` bypass token

**Changed**
- Hook entry prepended in `settings.json` so temper fires before cairn on `git commit`
- `settings.json` mutation wrapped in `flock` when available

**Fixed**
- Bypass regex unified to `# *(temper|suite):skip`

#### [0.1.0] — 2026-05-06

- `/temper` command: four-critic diff review (Correctness, Design, Risk, Coverage)
- Three-layer config resolution; diff targeting; secrets scan
- Output appended to `.claude/plans/TEMPER.md`
- Severity gate: blocks push on 🔴, bypass via `# temper:skip`
- `enforce-temper.sh` gating push, large/critical commits, merges to primary branches, long rebases, large stash pops
- `bin/temper` CLI

### whetstone

#### [0.1.5] — 2026-05-07

**Added**
- `hooks/enforce-whetstone.sh` with two non-blocking gates: stale/missing critique on `git push`/`commit`, and a once-per-project nudge on the first source-file write
- `install.sh` registers the hook via `_json_add_hook()` (Python/Node/jq fallback)

**Changed**
- `templates/CLAUDE.md`: full planning discipline with trigger/skip criteria, cross-suite integration rules, severity handoff table

#### [0.1.4] — 2026-05-07

- README "Bypassing whetstone" section and suite table
- `templates/CLAUDE.md` "Skipping the auto-trigger" section

#### [0.1.3] — 2026-05-06

**Changed**
- `/autocritic` writes to `.claude/plans/CRITIQUE.md` instead of the project root. **Breaking:** move an existing root `CRITIQUE.md` to preserve its history

#### [0.1.2] — 2026-05-06

- Re-run `/autocritic` after every user-requested plan modification

#### [0.1.1] — 2026-05-06

**Changed**
- Installers inject and remove `Read`/`Write` permissions automatically

**Fixed**
- Permission prompts when reading `whetstone.config` or writing `CRITIQUE.md`

#### [0.1.0] — 2026-05-06

- `/autocritic` command with three default critics (implementation, architecture, risk) and four optional (testing, complexity, API contract, cost/ops)
- Severity ratings 🔴 / 🟡 / 🟢; flags `--only`, `--skip`, `--severity`, `--off`, `--help`
- `bin/whetstone` CLI; three-layer config resolution; `whetstone.config.md` prose instructions
