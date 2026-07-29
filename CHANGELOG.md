# Changelog

All notable changes to aether are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

From 1.0.0 the four plugins live in this repository and share its version
number. Their individual histories are preserved under
[Pre-consolidation history](#pre-consolidation-history).

## [1.0.0] — 2026-07-28

bonsai, cairn, whetstone and temper now live in this repository. One clone, one
version, one installer, no network access at install time.

### Added

- `plugins/` — bonsai, cairn, whetstone and temper imported with full git
  history via `git subtree`
- `--suite` flag on all four plugin installers: installs commands, CLI and
  PostToolUse hook, but skips the PreToolUse hook and the plugin's own
  CLAUDE.md block, both superseded by the suite
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
