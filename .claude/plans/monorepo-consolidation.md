# Consolidate the aether suite into a single repo

## Context

`aether` today is a thin coordination layer that owns one hook and a CLI, but reaches
out to four *separate* GitHub repos at install time. Setting up a new machine needs
network access to five repos, nothing pins the five versions together, and the
installer's bonsai step is a `printf` telling you to go clone another repo by hand.

The goal is one repo you can clone on any machine and run one script to get the whole
`plan → build → review → ship` chain working, offline, at a version pinned to a single
git SHA.

### Decisions taken

| Decision | Choice |
|---|---|
| Name | Keep `aether` for repo *and* CLI — no new repo, no rename. History, release and remote stay put. |
| Distribution | `install.sh` only. No plugin-marketplace layer, so slash commands keep flat names (`/cairn-commit`, `/temper`, `/autocritic`). |
| Latent bugs | Fixed as part of the move, not deferred. |
| PostToolUse hooks | **Stop stripping them.** `post-cairn.sh` and `post-bonsai.sh` register normally alongside `enforce-suite.sh`. (Resolves the critique blocker.) |
| Gate duplication | **Fix in this change.** `enforce-suite.sh` sources the plugin gates instead of reimplementing them. |
| Versioning | **Unify everything to 1.0.0**, one CHANGELOG at the root. |

### What exploration established

All four plugin repos already exist locally as siblings, **all on `main`, all with zero
dirty files** — verified. So `git subtree` can import from local paths with no network
and no risk of capturing partial state.

| Repo | Path | How its installer finds its own files |
|---|---|---|
| bonsai | `/Users/valentinfigue/Code/bonsai` | `REPO_ROOT` via `BASH_SOURCE` → **already location-independent** |
| temper | `/Users/valentinfigue/Code/temper` | `REPO_DIR` via `dirname $0` + `cp` → **already location-independent** |
| cairn | `/Users/valentinfigue/Code/cairn` | `curl` from `raw.githubusercontent.com` → **must be repathed** |
| whetstone | `/Users/valentinfigue/Code/whetstone` | `curl` from `raw.githubusercontent.com` → **must be repathed** |

The key discovery: bonsai's installer writes **absolute** paths into `~/.claude.json`
([bonsai/install.sh:100](../../Code/bonsai/install.sh#L100)), so it works from anywhere.
The `FIXME` at [install.sh:175-182](../../Code/aether/install.sh#L175-L182) that skips
bonsai is obsolete the moment bonsai lives in the same clone. **Consolidation is itself
the bonsai fix.**

**Consequence to accept:** because bonsai registers absolute paths, the aether clone
becomes a permanent installed artifact — you cannot clone, install, then delete. Already
true of bonsai today; the plan makes it explicit in the README.

---

## Target layout

```
aether/
├── install.sh              # single entry point — installs all four locally
├── uninstall.sh            # thin wrapper around `aether uninstall`
├── bin/aether              # CLI (name unchanged)
├── hooks/
│   ├── enforce-suite.sh    # PreToolUse dispatcher — sources the gates below
│   └── post-suite.sh       # (not created — see Phase 6)
├── templates/CLAUDE.md     # the unified rules block
├── tests/                  # bats suite (new)
├── plugins/
│   ├── bonsai/     py/  ts/  src/  skills/  hooks/  bin/  install.sh
│   ├── cairn/      .claude/commands/  hooks/  bin/  install.sh
│   ├── whetstone/  .claude/commands/  hooks/  bin/  install.sh
│   └── temper/     .claude/commands/  hooks/  bin/  install.sh
├── .github/workflows/      # hoisted from plugins/bonsai (Phase 2)
├── BYPASS.md  README.md  CHANGELOG.md  LICENSE
```

The suite layer (`hooks/`, `bin/`, `templates/`) stays at the **root** rather than
becoming `plugins/suite/`. This is deliberate: it keeps the URL
`raw.githubusercontent.com/ValentinFigue/aether/main/hooks/enforce-suite.sh` valid, so
existing 0.1.0 installs can still self-update their hook.

---

## Phase 1 — Import the four repos with history

```bash
cd /Users/valentinfigue/Code/aether
git checkout -b feat/monorepo

for p in bonsai cairn whetstone temper; do
  git subtree add --prefix=plugins/$p "../$p" main
done
```

Local paths are valid subtree remotes, so this is offline and fast. No prefix collides,
so each repo's `LICENSE`/`README.md`/`CHANGELOG.md` lands harmlessly under its own
`plugins/<p>/`.

**Check before proceeding:** confirm bonsai's `.gitignore` kept `.venv/`,
`node_modules/`, `.mypy_cache/`, `.ruff_cache/`, `.pytest_cache/` out of its *history* —
all five exist on disk in `/Users/valentinfigue/Code/bonsai`. Verify with
`git log --oneline --all -- plugins/bonsai/node_modules | head`; if non-empty, redo
bonsai's import with `--squash`.

**Rollback for the whole plan:** do not merge to `main` until verification passes.
Rollback is `git checkout main && git branch -D feat/monorepo`.

## Phase 2 — Hoist bonsai's CI

GitHub only runs workflows at the repo root, so `plugins/bonsai/.github/workflows/`
would be silently dead.

```bash
mkdir -p .github/workflows
git mv plugins/bonsai/.github/workflows/<each>.yml .github/workflows/bonsai-<each>.yml
```

Add `paths: ['plugins/bonsai/**']` to each hoisted workflow so bonsai's CI does not fire
on shell-only changes, and fix any `working-directory` / relative path to be
`plugins/bonsai`-relative.

## Phase 3 — Make cairn and whetstone read from disk

The change that removes the network dependency. Follow the pattern temper already uses
([temper/install.sh:26](../../Code/temper/install.sh#L26)), but with `BASH_SOURCE`
rather than `$0` so the scripts resolve when invoked as `bash plugins/cairn/install.sh`
from the repo root:

```bash
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
```

**`plugins/cairn/install.sh`** — replace each `curl -fsSL -o <dest> <raw-url>` with `cp`:

| Currently curled | Becomes |
|---|---|
| `.claude/commands/$name` (×4, line ~166) | `cp "$REPO_DIR/.claude/commands/$name"` |
| `bin/cairn` (line ~211) | `cp "$REPO_DIR/bin/cairn"` |
| `hooks/enforce-cairn.sh` (line ~226) | `cp "$REPO_DIR/hooks/enforce-cairn.sh"` |
| `hooks/post-cairn.sh` (line ~232) | `cp "$REPO_DIR/hooks/post-cairn.sh"` |

**`plugins/whetstone/install.sh`**:

| Currently curled | Becomes |
|---|---|
| `.claude/commands/autocritic.md` (line ~103) | `cp "$REPO_DIR/.claude/commands/autocritic.md"` |
| `bin/whetstone` (line ~161) | `cp "$REPO_DIR/bin/whetstone"` |

### Add a `--suite` flag to all four plugin installers

In suite mode a plugin should install its commands, CLI and **PostToolUse** hook, but
skip: (a) its **PreToolUse** hook install and registration — `enforce-suite.sh`
supersedes it, and Phase 5 vendors the gate directly; and (b) its own
`<!-- cairn:start -->`-style CLAUDE.md injection, since `templates/CLAUDE.md` supersedes
it.

**bonsai needs this flag too**, and its arg parser is the strict one — it ends in
`*) echo "Unknown option: $arg"; exit 1`. cairn/whetstone/temper silently ignore unknown
flags, so bonsai is the one that hard-fails if the `case` is not updated.

## Phase 4 — Rewrite the root `install.sh`

Replace the three `curl … | bash` blocks and the bonsai `printf` skip
([install.sh:171-206](../../Code/aether/install.sh#L171-L206)):

```bash
FAILED=0
for p in cairn whetstone temper; do
  bash "$SCRIPT_DIR/plugins/$p/install.sh" $SCOPE_ARG --suite \
    || { printf '  ✗ %s failed to install\n' "$p"; FAILED=1; }
done
```

**bonsai** gets its own branch — real prerequisites (`uv`, `node`, `npm`, `python3`) and
a build step. Probe and degrade gracefully rather than failing the whole suite:

```bash
if command -v uv &>/dev/null && command -v node &>/dev/null && command -v npm &>/dev/null; then
  printf '  bonsai: building py/ and ts/ — this takes a minute...\n'
  bash "$SCRIPT_DIR/plugins/bonsai/install.sh" --suite || FAILED=1
else
  printf '  bonsai: skipped — requires uv, node, npm. Install them, then run:\n'
  printf '          bash %s/plugins/bonsai/install.sh\n' "$SCRIPT_DIR"
fi
```

The progress line matters: bonsai runs `uv sync` and `npm install && npm run build
--silent`, minutes of otherwise total silence. Add a `--no-bonsai` flag for a shell-only
install, and exit non-zero at the end if `FAILED`.

## Phase 5 — Deduplicate the gate logic

Today `enforce-suite.sh` (467 lines) reimplements all four plugin gates inline. Every
future gate change must be hand-mirrored. The monorepo makes this fixable.

**The obstacle:** the four plugin hooks are *linear scripts, not function libraries* —
verified. None defines a gate function (only temper has `_config_get`); each does
`input=$(cat)` at top level; each calls bare `exit 0` / `exit 1` throughout. Sourcing
them as-is would kill the parent on the first `exit`, and the first `cat` would consume
stdin for all the rest.

### Refactor each plugin hook to a dual-mode shape

Applies identically to all four
([cairn/hooks/enforce-cairn.sh](../../Code/cairn/hooks/enforce-cairn.sh) 127 lines,
[whetstone](../../Code/whetstone/hooks/enforce-whetstone.sh) 86,
[temper](../../Code/temper/hooks/enforce-temper.sh) 217,
[bonsai](../../Code/bonsai/hooks/enforce-bonsai.sh) 99):

1. Wrap the body in `gate_<plugin>()`; the function reads the pre-parsed globals
   `$tool_name` and `$cmd_or_path` instead of calling `cat`.
2. Convert every top-level `exit N` inside that body to `return N`.
3. Guard `set -euo pipefail` so it only applies standalone — sourcing a file that sets
   `-e` would change the parent's shell options and defeat `enforce-suite.sh`'s
   fail-open wrapper.
4. Append a standalone entrypoint so direct invocation still works unchanged:

```bash
if [ -z "${SUITE_MODE:-}" ]; then
  set -euo pipefail
  input=$(cat)
  # …existing stdin parse, setting tool_name / cmd_or_path…
  gate_cairn; exit $?
fi
```

5. Namespace-prefix any helper that could collide across the four sourced files —
   temper's `_config_get` becomes `_temper_config_get`.

### Reduce `enforce-suite.sh` to a dispatcher

It keeps only what is genuinely suite-level: the stdin parse, bypass resolution
(`# aether:skip`, `# suite:skip`, per-plugin skips), `_plugin_enabled`, and the
accumulating dispatch that already exists at lines 450-467. The ~400 lines of copied
gate bodies are deleted in favour of:

```bash
GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/gates"
export SUITE_MODE=1
for g in cairn whetstone temper bonsai; do
  [ -f "$GATE_DIR/enforce-$g.sh" ] && . "$GATE_DIR/enforce-$g.sh"
done
```

Three details this must get right:

- **Source before dispatch.** The loop only *defines* `gate_cairn` and friends; the
  existing dispatch block then calls them. It must run above line 450, and the inline
  definitions must be deleted first or they will shadow the sourced ones.
- **`export SUITE_MODE=1` before the loop**, not `SUITE_MODE=1 . file` as a prefix —
  whether an assignment prefix on the `.` special builtin persists differs between
  bash's POSIX and default modes. Exporting once sidesteps the question entirely.
- **`gate_whetstone_write` disappears.** enforce-suite.sh currently splits whetstone
  across two functions (Bash path and Write/Edit path), but
  [whetstone's own hook](../../Code/whetstone/hooks/enforce-whetstone.sh) already
  handles both by branching on `$tool_name`. The two collapse into the single sourced
  `gate_whetstone`, and the Write/Edit dispatch branch calls it directly.

### Where the gates live at runtime

`enforce-suite.sh` is installed to `~/.local/share/aether/`, but the plugin hooks live
in the clone. **`install.sh` copies them into `~/.local/share/aether/gates/`** so the
hook resolves them via `$(dirname "$BASH_SOURCE")/gates/` — self-contained, no manifest
lookup, no dependence on the clone path at hook runtime. This matters because the hook
fires on *every* Bash/Write/Edit call and must be fast and robust.

`aether update` re-copies `gates/` as part of re-running the installer.

## Phase 6 — Stop destroying the PostToolUse hooks

**This was the critique blocker.** [bonsai/install.sh:193-214](../../Code/bonsai/install.sh#L193-L214)
registers a PostToolUse reference-drift hook — bonsai's newest feature, HEAD commit
`78a95a5`. cairn registers `post-cairn.sh`, which drives two real triggers (post-temper
→ `/cairn-commit`, version bump → `/cairn-changelog`). `enforce-suite.sh` has **zero**
PostToolUse coverage, yet aether's `STALE` list strips both — so aether installs bonsai
and then immediately deletes it.

**Fix:** remove `"post-cairn"` and `"post-bonsai"` from the `STALE` array in all three
places it appears — [install.sh:46-47](../../Code/aether/install.sh#L46-L47),
[uninstall.sh](../../Code/aether/uninstall.sh), and
[bin/aether:200-201](../../Code/aether/bin/aether#L200-L201). Keep stripping the four
`enforce-*` PreToolUse entries; those are genuinely superseded.

No `hooks/post-suite.sh` is created — the two per-plugin PostToolUse hooks stand on
their own.

Note the asymmetry for the README: PreToolUse is unified, PostToolUse is per-plugin.

## Phase 7 — Remaining bug fixes

1. **The advertised curl one-liner is broken today.** The README promotes
   `curl … install.sh | bash`, but the script `cp`s `$SCRIPT_DIR/hooks/enforce-suite.sh`
   ([install.sh:220](../../Code/aether/install.sh#L220)) and `$SCRIPT_DIR/bin/aether`
   ([install.sh:252](../../Code/aether/install.sh#L252)), neither of which exists when
   piped to bash. **Fix:** delete the one-liner from the README. Clone-then-install is
   now the only supported path — correct anyway, since bonsai needs the clone to persist.

2. **MCP permission wildcards never match.** Both aether
   ([install.sh:125](../../Code/aether/install.sh#L125)) and bonsai
   ([bonsai/install.sh:136](../../Code/bonsai/install.sh#L136)) write
   `mcp__bonsai_py__*` with **underscores**, but the servers register as `bonsai-py` /
   `bonsai-ts`, so real tool names are `mcp__bonsai-py__pyrename`. The same bug sits in
   [bonsai/.claude-plugin/hooks.json](../../Code/bonsai/.claude-plugin/hooks.json) as
   matchers `mcp__bonsai_py__(pyrename|pymove|pymovesymbol|pysignature)`, so the dry-run
   confirmation prompt on mutating refactors never fires either. **Fix:** repo-wide
   `grep -rn 'bonsai_py\|bonsai_ts'` sweep; correct all hits, in every python/node/jq
   branch.

3. **Plugin installs report success unconditionally** — `curl … || true` followed by an
   unconditional `printf '  ✓ %s installed'`. Fixed by the `FAILED` pattern in Phase 4.

4. **`_json_remove_stale_hooks` is python3-only** with no node/jq fallback, unlike its
   two siblings — it silently no-ops without python3, leaving duplicate hooks. **Fix:**
   add node and jq branches mirroring `_json_register_suite_hook`.

5. **No backup before mutating `~/.claude/settings.json` and `~/.claude/CLAUDE.md`.**
   Every helper is `python3 … > "$f.tmp" && mv "$f.tmp" "$f"`; partial output on error
   truncates and overwrites the real file. Your global CLAUDE.md carries the 236-line
   aether block plus your own content. **Fix:** one-time `cp "$f" "$f.bak"` before the
   first mutation — same change as item 4.

6. **`plugins/bonsai/.mcp.json`** holds relative paths (`py`, `ts/dist/server.js`) and is
   project-scoped to the bonsai directory. It still resolves when working *inside*
   `plugins/bonsai`, so leave it — but confirm it is not picked up at the aether root.

## Phase 8 — Update `bin/aether`

- **`cmd_update`** ([bin/aether:143-172](../../Code/aether/bin/aether#L143-L172)) drops
  the `PLUGIN_URLS` array and the hook self-download. It becomes
  `git -C "$repo" pull --ff-only && bash "$repo/install.sh" $scope_arg`.
- To find `$repo`, **add `repo=$SCRIPT_DIR` to the manifest** written at
  [install.sh:294-298](../../Code/aether/install.sh#L294-L298), read via the existing
  `_manifest_get` helper. Error clearly if the recorded path no longer exists.
- Add the missing `version` subcommand. `status`, `enable`, `disable` are unaffected —
  they read `<plugin>.config` files.
- `cmd_uninstall` duplicates `uninstall.sh` almost verbatim. Reduce `uninstall.sh` to a
  thin wrapper that execs the CLI, so there is one implementation. It must also remove
  `~/.local/share/aether/gates/`.

## Phase 9 — Unify versions to 1.0.0

Currently: aether 0.1.0 (README says 1.0.0 — drift), cairn 0.3.1, bonsai 0.1.0,
whetstone and temper their own.

- Set `VERSION="1.0.0"` in every `install.sh` and `bin/<name>` across the repo.
- Fold each `plugins/<p>/CHANGELOG.md` into the root `CHANGELOG.md` as historical
  sections, then delete the per-plugin files.
- `aether status` reports one version for the suite.

## Phase 10 — Tests

aether has zero tests — TEMPER.md item 6, still open. With Phase 5 refactoring ~530
lines across five hook files, a manual checklist is not credible verification. Add a
`tests/` bats suite covering:

- **Dual-mode equivalence** — the highest-value test. For each of the four gates, feed
  the same JSON payload standalone and via `SUITE_MODE=1`, and assert identical exit
  code and output. This is what proves the Phase 5 refactor preserved behaviour.
- Bypass markers: `# aether:skip`, `# suite:skip`, and each per-plugin skip.
- Fail-open: a gate that errors must not block the tool call.
- Install idempotence: run `install.sh` twice, assert exactly one PreToolUse hook.

## Phase 11 — Docs and archival

- **README.md** — rewrite `## Install` around clone-then-run; delete the curl one-liner
  and the four standalone `curl` commands under `## Installing plugins individually`
  (replace with `bash plugins/<name>/install.sh`); state that the clone must persist;
  document `--no-bonsai`, `--suite`, and the uv/node/npm prerequisites; explain the
  PreToolUse-unified / PostToolUse-per-plugin asymmetry; fix the `v1.0.0` sample output.
- **CHANGELOG.md** — `## [1.0.0]` with `### Added` (monorepo, bonsai auto-installed,
  `--suite` / `--no-bonsai` / `aether version`, bats suite), `### Changed` (local
  installs replace network fetch, `aether update` uses git pull, gates deduplicated,
  versions unified), `### Fixed` (Phase 6 + the six items in Phase 7 — call out that
  removing `curl | bash` closes a remote-code-execution path), `### Removed` (curl
  one-liner, per-plugin CHANGELOGs).
- **BYPASS.md / templates/CLAUDE.md** — marker table and gate semantics are unchanged;
  update the links that point at the four separate repos to `plugins/<name>/`.
- **Archive, do not delete, the four GitHub repos** — read-only, each with a README
  stating the frozen version and pointing at aether. Archived repos stay fetchable, so
  anyone's existing `curl` one-liner keeps working instead of breaking silently. Do this
  **only after verification passes**.

---

## Verification

1. **Import integrity** — `git log --oneline plugins/cairn | tail -5` shows cairn's
   original commits, not one squashed blob. Repeat for all four. Then
   `diff -r --exclude=.git plugins/temper /Users/valentinfigue/Code/temper` reports only
   ignored/untracked noise.

2. **No network at install time** — the decisive check:
   ```bash
   grep -rn 'raw.githubusercontent' install.sh bin/aether plugins/*/install.sh
   ```
   Must return nothing outside comments and doc strings.

3. **Dual-mode equivalence** — `bats tests/` green. This gates Phase 5; do not proceed
   if it fails.

4. **Dry run** — `bash install.sh --global --dry-run` completes and mentions all four
   plugins including bonsai.

5. **Real install into a throwaway HOME.** Use `env` so the override is scoped to the
   one command — do **not** `export HOME`, which would silently redirect every later
   command in the session, including Claude Code's own `~/.claude` reads:
   ```bash
   env HOME="$(mktemp -d)" bash install.sh --global --claude-md
   ```
   Then assert, against that temp HOME:
   - `.claude/commands/` holds `cairn-commit.md`, `cairn-pr.md`, `cairn-changelog.md`,
     `cairn-summary.md`, `temper.md`, `autocritic.md`
   - `.local/share/aether/enforce-suite.sh` exists, executable, and
     `.local/share/aether/gates/` holds all four `enforce-*.sh`
   - `settings.json` has exactly **one** `PreToolUse` hook (`enforce-suite.sh`, no
     `enforce-cairn`/`enforce-temper`/`enforce-whetstone`/`enforce-bonsai` survivors)
     and **both** `post-cairn.sh` and `post-bonsai.sh` present under `PostToolUse`
   - `permissions.allow` contains `mcp__bonsai-py__*` with a **hyphen**
   - `CLAUDE.md` has one `<!-- aether:start -->` block and no `<!-- cairn:start -->`
   - `aether.manifest` has `version=1.0.0` and a `repo=` line pointing at the clone
   - a `settings.json.bak` was created

6. **Hook fires correctly** — feed it the real payload shape:
   ```bash
   echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' \
     | ~/.local/share/aether/enforce-suite.sh; echo "exit=$?"
   ```
   Expect `exit=1` with a cairn weak-message nudge. Then the same command with
   `# aether:skip` appended must give `exit=0` and no output.

7. **Standalone hooks still work** — `SUITE_MODE` unset,
   `echo '<payload>' | plugins/cairn/hooks/enforce-cairn.sh` behaves exactly as before
   the refactor. Phase 5 must not break direct use.

8. **Failure path** — temporarily rename `plugins/cairn/bin/cairn`, re-run the install,
   confirm it prints `✗ cairn failed` and exits non-zero rather than a green tick.

9. **bonsai end-to-end** (needs uv/node/npm) — `~/.claude.json` registers `bonsai-py`
   with an absolute path under `<clone>/plugins/bonsai/py`; restart Claude Code and
   confirm `mcp__bonsai-py__pyfindrefs` resolves. Verify the graceful-skip branch by
   running the install with `uv` masked off `PATH`.

10. **`aether update`** — from a clean tree, `git pull --ff-only` then re-run of the
    local installer, with no network fetch of plugin assets.

11. Only after all of the above: merge `feat/monorepo` to `main`, tag `v1.0.0`, then run
    the Phase 11 archival.
