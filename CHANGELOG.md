# Changelog

All notable changes to aether are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

From 1.0.0 the four plugins live in this repository and share its version
number. Their individual histories are preserved under
[Pre-consolidation history](#pre-consolidation-history).

## [Unreleased]

### Changed

- **The hook starts one interpreter per tool call instead of three.** `enforce-suite.sh`
  parsed stdin with python3, and then temper and cairn each started python3 again to
  analyse a command the dispatcher had already read — three starts on a `git commit`,
  two on a Write, at roughly 18ms each, on a path that runs on every Bash, Write and
  Edit of every session. There is now one parse, `aether_parse_command`, and temper's,
  cairn's and bonsai's rules are bash, git and awk. Every rule was ported literally and
  diffed against the old implementation over the same inputs — 35 commit messages, all
  five of temper's branches at, above and below each threshold, 26 bonsai commands —
  and all three are byte-identical. `tests/test_hookcost.sh` counts interpreters rather
  than timing them, so a loaded CI machine cannot raise a false alarm.

- **One nudge per tool call.** A single `git commit` could print fifteen lines from
  three plugins. The hook now prints the earliest lifecycle stage with something to say
  and names the rest on one line; `aether status --notes` shows what was held back.
  Nudge fatigue is how guardrails die — the fastest way to stop the noise is
  `# aether:skip` on everything, which is worse than any single nudge.

  A **block** is never budgeted. temper's unreviewed-push and critical-path-commit
  messages print in full and alone, and the nudges beside them are dropped rather than
  appended. Suppressing one would turn "you cannot push unreviewed" into "you might not
  hear about it".

### Fixed

- **A bypass marker anywhere in a command silenced the suite.** Every gate grepped for
  its own marker as a substring, so a commit *documenting* one turned the gates off:

  ```bash
  git commit -m "docs: explain the # aether:skip marker"   # all four went silent
  ```

  A marker is now only honoured in a trailing comment — after a `#` that starts a word,
  outside quotes, with nothing but further markers behind it. The five greps were also
  three different spellings of the whitespace (`#\s*`, `# *`, `#[[:space:]]*`) across
  three files; there is now one implementation, and a test asserts all four gates and
  the dispatcher agree on the same string. See [BYPASS.md](BYPASS.md), which now also
  states the threat model plainly: the agent writes the commands the hook inspects, so
  every nudge is advisory by construction, and blocks are the one place that bites.

- **`# aether:skip` did nothing for a standalone plugin install.** It was resolved only
  by the dispatcher. Both it and `# suite:skip` now work either way.

### Added

- `aether status --notes` — the nudges the budget held back on the last tool call.
  Recorded in `.aether/out/.notes`, project-relative and never through
  `aether_out_dir`, whose `~/.aether/out` fallback is what made v1.1.0's nudge sentinel
  once-per-machine instead of once-per-project.

## [1.4.0] — 2026-07-30

### Fixed

- **The plan critique never happened automatically, for seven separate reasons.** The
  gate globbed `./.claude/plans/*.md` while Claude Code's plan mode writes to
  `~/.claude/plans/`, so **it had never once seen a plan written by plan mode** — it
  compared whatever stale file happened to be in the project directory. The
  `/critique-plan` command used a third, different discovery rule and neither looked
  there either. Staleness was mtime-based, so re-saving an unchanged plan invalidated
  an accurate critique and any copy or checkout reordered the answer. One `CRITIQUE.md`
  covered a whole project, so critiquing plan A satisfied the gate for plan B. The
  critique could not persist at all in plan mode, which permits writing only the plan
  file. The source-write nudge used one empty sentinel per project, so it was
  decorative after the first day. And nothing recorded which plan a project was
  working on.
- **The suite hook's matcher was hardcoded** in `_json_register_suite_hook`, so
  widening a plugin's matcher in its manifest did nothing — `suite_owned` hooks are
  replaced by the suite hook, which used the literal. It is now the union of every
  `suite_owned` PreToolUse matcher the manifests declare, in a fixed order so it stays
  stable and testable.

### Added

- **A critique lives inside the plan it critiques**, behind
  `<!-- aether:critique sha=… -->` … `<!-- /aether:critique -->`. That is the only file
  writable in plan mode, and it is per plan by construction. The `sha` covers the plan
  with that block removed, so re-saving does not invalidate an accurate critique while
  appending a section does — and editing the critique text does not mark the plan
  stale. Trailing blank lines are normalised out, because appending the block naturally
  adds one and that alone used to read as a change.
- **`ExitPlanMode` nudges** — presenting a plan is exactly when its critique should
  already exist. It **prints and returns 0, always**: whether Claude Code delivers
  PreToolUse for that tool, and what it does with a non-zero exit, could not be
  determined from outside it, and a nudge that trapped you in the mode it was nudging
  about — while intercepting the calls the critique needs — would be far worse than no
  nudge. The gate records the first time it sees such a payload and `aether plan status`
  reports it, so the open question answers itself from use rather than from a guess.
- **`plugins/whetstone/hooks/post-whetstone.sh`** — records which plan this project is
  working on. Silent: plan mode rewrites the plan repeatedly while it is being built,
  so nudging here would fire on every edit.
- **`aether plan status | path | hash`.** The failure this replaces was invisible for
  as long as it took to notice; "which plan does the gate think I am working on, and
  does it consider it critiqued" is now one command.
- `aether_sha` extracted from `aether_hash_project`, which hardcoded two filenames and
  so could not be reused. One hasher, one fail-closed path.
- `tests/test_whetstone_plan.sh` — 42 assertions, 23 of which fail against the previous
  code.

### Changed

- The source-write nudge is keyed to the plan's hash, so it fires once per uncritiqued
  plan rather than once per project for ever. The pre-1.4 sentinel is still honoured, so
  an existing project does not get one fresh nudge on upgrade.
- `/critique-plan` discovers the plan via `aether plan status`, the same answer the gate
  uses, instead of a third rule of its own.

## [1.3.1] — 2026-07-30

### Fixed

- **Folding a nested install into an area left its trust entry behind.** The
  subfolder may have been trusted in its own right, and after the fold its config no
  longer exists — so the entry could never match again and `aether doctor` reported it
  as `changed` for ever. A permanent spurious warning in the one tool whose job is
  signalling teaches people to ignore it, which is the failure mode the doctor exists
  to prevent. `aether migrate` now drops the entry, and `_trust_forget_path` exists so
  forgetting a project is not limited to the current directory.

  Found by running `aether doctor` on a machine right after the 1.3.0 migration, not
  by a test — which is why there is now a test, verified to fail against 1.3.0.

## [1.3.0] — 2026-07-30

### Added

- **`[project:<path>]` — one config for a monorepo.** `[project]` assumed one test
  command for one tree, so the only way to give a subfolder its own toolchain was to
  run `aether install` inside it. A real repo doing that had two thirds of itself
  unconfigured, gates that fired only when the shell was in that directory, and trust
  granted to a subfolder rather than the repo. Areas are named for the directory their
  commands run in, and files map to areas by longest matching path prefix — the way a
  CI paths filter does.
- **`aether check [path…] [--all] [--raw]`** — runs each area's commands in that
  area's directory, defaulting to files changed against the base branch. It is the
  **only** thing that executes `[project]` commands: `/critique-diff` and
  `/critique-pr` now call it instead of running commands themselves, so trust has one
  enforcement point rather than three.
- **`check.<name>`** for the CI steps that fit no standard key — a lockfile check, a
  single-migration-head check. Without it those were silently dropped from any config.
- **`aether project for <file…>`** — which areas those files belong to, the primitive
  the critics and `aether check` share.
- `aether migrate` folds a nested install into an area: `backend/.aether/` becomes
  `[project:backend]`. Only within the same git work tree, since a vendored repo in a
  subdirectory is not an area; where a non-`[project]` key differs it keeps the
  parent's value and reports the conflict rather than merging silently; the old
  directory is left at `backend/.aether.bak`.
- trellis learns areas: `working-directory:` and paths-filter blocks in CI become one
  `[project:<path>]` per area. A single-language repo still gets a plain `[project]`.
- `tests/test_project.sh` — 56 assertions.

### Fixed

- **`aether trust` showed no commands at all on a monorepo.** The preview read only
  `[project]`, so a repo whose commands all live in areas authorised thirteen of them
  while displaying none — turning the preview into a formality, which is the one thing
  it exists to prevent. It now walks every area, and reads the keys straight from the
  file rather than through the trust-gated resolver, which during a preview returns
  almost nothing by definition. Found by running it on a real repo, not by a test.
- **A path section bypassed the trust gate entirely.** The check was
  `[ "$section" = project ]`, an equality test, so `[project:web]` returned its
  commands from an untrusted repo. Harmless only while nothing read them — and
  `aether check` is exactly something that reads them, which is why the fix and its
  assertion landed before the syntax was usable.
- **The first failing check aborted the whole run.** `out=$( … ); rc=$?` is an
  assignment from a failing command substitution, which under `set -e` exits the
  shell — so every check after the first failure went unreported, on the primary path.
- Command keys no longer inherit from `[project]` into an area. A command written for
  the repo root has no correct working directory inside a subdirectory; the first draft
  of this design got that wrong in both directions.

### Changed

- `aether config show project` lists every area, grouped by area; `config show
  project:web` lists one. `config doctor` walks every area, so a missing binary is
  reported against the toolchain that needs it rather than against the root, and it
  flags an area whose directory no longer exists.
- Section names are normalised on read, so `[project:web]`, `[project:./web]` and
  `[project:web/]` are one area.
- This repo declares `[project:plugins/bonsai/py]` and `[project:plugins/bonsai/ts]`,
  so `typecheck` is no longer unset — the tree is bash at the top with Python and
  TypeScript inside one plugin, which is the case that motivated this.

## [1.2.0] — 2026-07-30

### Added

- **`aether doctor`** — one command asking whether the state on disk matches what
  the manifests declare. It exists because every bug that mattered in 1.1.0 shared a
  shape: the tool reported success and had done nothing. It checks that every hook in
  `settings.json` exists and is executable, that no script is registered twice, that
  the suite hook is registered exactly once, that each declared MCP server is
  registered with a resolvable command and existing paths, that every artefact the
  install manifest records is present, that no pre-rename command is still in the
  palette, that no pre-1.0 location survives, that the recorded clone is still there,
  that the declared permissions are present, that each gate parses, and that no trust
  entry points at a directory that no longer exists. Every finding names its fix.
- **`aether doctor --fix`** — the three repairs where the right action is
  unambiguous: deregister a hook whose script is gone, drop a duplicate registration
  keeping the copy the engine installed, and prune dead trust entries. It works out
  what to do before touching anything, so a run with nothing to fix leaves the home
  directory byte-identical — `.bak` included.
- **`aether doctor --deep`** — additionally handshakes each MCP server, which is the
  check whose absence let the engine ship for six commits registering none.
- **`aether trust list` and `aether trust prune`** — every recorded project with its
  state (`ok`, `changed`, `dead`), and removal of entries whose directory is gone.
  Nothing pruned them before, so a path deleted months ago still granted consent if a
  directory reappeared there. Reported by default, pruned only on request: a path can
  be temporarily unmounted, so silently forgetting consent would be the wrong default.
- `tests/test_doctor.sh` — 53 assertions, each against the state of an actual 1.1.0
  bug rather than a synthetic stand-in.

### Fixed

- **On a jq-only machine the doctor silently checked nothing.** `~/.claude.json` does
  not exist until bonsai installs, and jq exits non-zero on a missing file — so the
  probe read as "cannot inspect settings.json" and every hook check was skipped.
  python3 and node swallow the missing file in their loaders, which is why the two
  backends disagreed. Caught by the backend-equivalence assertion.

### Changed

- `aether config doctor` now calls the same implementation as `aether doctor`'s
  config half rather than carrying its own copy. It keeps working, and it stays
  scoped to config and trust.
- README opens on the problem the suite solves, with a before/after example, rather
  than on the plumbing of combining four plugins. Adds **Quick start** (three
  commands, `/draft-config` included). The roadmap now states the
  intent to support agents beyond Claude Code. Trimmed from 953 to ~790 lines.

## [1.1.0] — 2026-07-30

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
- **`tests/acceptance.sh`** — end-to-end checks against a throwaway HOME, for what
  a unit test cannot reach: a path containing spaces, nine hostile hook inputs
  (none may exit 2 or write to stderr), `--dry-run` leaving the home directory
  byte-identical with bonsai included, four consecutive installs producing
  identical state, upgrading from the last tag with no dangling hooks, and the
  hook's per-tool-call cost measured against that tag rather than an absolute
  budget. `--full` additionally builds bonsai and handshakes both MCP servers.
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
- **`config doctor` missed a missing binary whenever the command was a pipeline.**
  It checked only the first word, so `git ls-files | xargs shellcheck` reported
  nothing on a machine with no shellcheck — the exact silent skip the check exists
  to catch. Every command position is now checked, including past wrappers like
  `xargs` and `env` that put the real command in argument position.
- **The PreToolUse hook got 25% slower**, from 81ms to 105ms per tool call — and
  it runs on every Bash, Write and Edit. Cause: resolving a key ran one `awk` per
  key per layer, which cost nothing before only because there was no config file
  to read. Seeding a starter config at install made that path always-on, at twelve
  awk processes per invocation. Both files are now dumped once into a shell
  variable and every lookup answers from it: **1 awk process, 86ms.** A test
  counts processes rather than timing, so it stays meaningful on a loaded CI box,
  and another asserts the cached and uncached paths resolve identically —
  including the trust gate on `[project]`, which the dump reproduces from a layer
  column.
- **A CRLF config file read as an empty one.** `[temper]\r` does not match
  `/^\[.*\]$/`, so the section was never entered and *every* key in the file
  silently did nothing — including `enabled: false`, which made `aether disable`
  appear not to work. A regression against 1.0.0, whose `grep`-based reader at
  least returned the value. All five parsers now normalise CRLF.
- **`config set` silently corrupted any value containing a backslash.**
  `awk -v v="$value"` performs escape processing on its argument, so `\.sql`
  became `.sql` and a regex like `\d+` became `d+`. The default
  `temper.critical_paths` contains `\.sql` and `\.env`, and migration uses the
  same writer — so an upgrade quietly rewrote it. Values now come through the
  environment, where no escape processing happens.
- **Every install grew CLAUDE.md by one line.** Removing the sentinel block took
  the block but not the blank line that separated it, and the re-append added a
  fresh one: 295 lines, then 296, then 297. Trailing blanks are now stripped
  before re-appending, so the splice is byte-idempotent.
- **`aether update` corrupted itself mid-run.** It executes from
  `~/.local/bin/aether` and copies a new `bin/aether` over that same path, and
  `cp` truncates and rewrites in place. bash reads a script incrementally as it
  executes, so the byte offsets shifted under the interpreter and it resumed
  mid-token — `syntax error near unexpected token ';;'` from inside the
  dispatcher's `case`, *after* the install had reported success. Every copy now
  goes through a temp file in the destination directory and lands with a rename,
  so a process already executing the old file keeps its inode and runs to
  completion. Latent before this branch; the file growing made it reliable.
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

### Changed

- **One config resolver instead of two.** A cached path and an uncached path each
  implemented layer precedence and the `[project]` trust gate separately — the
  shape that drifts. There is now one path over a dump of all four layers
  (pre-1.0 global, pre-1.0 project, global, project), which also removes the
  special case that read the pre-1.0 files only when the new ones were empty:
  ordering the layers is equivalent and simpler. A duplicated key inside one file
  still takes the first occurrence, as `head -1` used to give.
- **aether now uses its own config.** `.aether/config` and `.aether/rules.md` are
  committed, so its critics run its real test command and read its real house
  rules. The suite previously shipped without either, which meant the tool did
  not eat its own dog food and nothing noticed.

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
