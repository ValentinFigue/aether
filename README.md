# aether

Aether binds bonsai, whetstone, temper, and cairn into a single coordinated suite — one repo, one install, one bypass convention, one hook that knows the order of things.

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

```
manifests  ──▶  bin/aether (engine)  ──▶  ~/.claude/commands/
                     │                    ~/.claude/settings.json
                     │                    ~/.claude.json  (MCP)
                     └──────────────────▶ <hookdir>/enforce-suite.sh
                                          <hookdir>/gates/enforce-*.sh
```

### Adding a plugin

Write a manifest and put the assets beside it. There is no installer to write —
`aether install <name>` and `aether uninstall <name>` work from the manifest
alone, and the plugin appears in `aether status` because it exists.

---

## What changes in your environment

| What | Where |
|---|---|
| `enforce-suite.sh` | `~/.local/share/aether/enforce-suite.sh` (global) or `.claude/hooks/enforce-suite.sh` (local) |
| Plugin gates | `<hook dir>/gates/enforce-<plugin>.sh` — sourced by the suite hook |
| Plugin hooks | `<hook dir>/plugin-hooks/` — PostToolUse scripts the suite has no equivalent for |
| Hook registration | `settings.json` — one `PreToolUse` entry, matcher `Bash\|Write\|Edit\|MultiEdit` |
| Permissions | `settings.json` — `Bash`, `Read`, `Write`, plus each installed plugin's own (bonsai adds `mcp__bonsai-*__*`) |
| `aether` CLI | `~/.local/bin/aether` |
| Slash commands | `~/.claude/commands/` — `critique-*.md`, `draft-*.md` |
| CLAUDE.md block | injected with `--claude-md` flag |
| Install manifest | `~/.claude/aether.manifest` |

Per-plugin `PreToolUse` hooks are removed during install, since `enforce-suite.sh` supersedes them. `settings.json` and `CLAUDE.md` are copied to `.bak` before the first change.

### PreToolUse is unified; PostToolUse is not

The suite hook covers the `PreToolUse` phase only. cairn and bonsai also register `PostToolUse` hooks — `post-cairn.sh` (suggests `/draft-commit` after a clean review, `/draft-changelog` after a version bump) and `post-bonsai.sh` (reference-drift check after a rename-shaped edit). These have no equivalent in the suite hook, so they are left registered per-plugin rather than removed.

---

## The workflow

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

`enforce-suite.sh` skips any plugin whose `<plugin>.config` says `enabled: false`, and any gate that is not installed. All gates are non-blocking nudges, except temper which blocks high-risk operations (push without review, critical-path commit).

---

## CLI reference

```
aether install [plugin...] [global] [--claude-md] [--no-bonsai] [--dry-run]
                                         Install the suite, or just the named plugins
aether uninstall [plugin...] [global] [--claude-md]
                                         Remove a plugin, or the suite layer itself
aether status                            Plugin state, gates, clone path, version
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

**Example output of `aether status`:**

```
aether v1.0.0

  bonsai       enabled  MCP: bonsai-py bonsai-ts
  whetstone    enabled
  temper       enabled
  cairn        enabled

  Suite hook: enforce-suite.sh registered (global)
  Gates:      4 loaded from /Users/you/.local/share/aether/gates
  Clone:      /Users/you/Code/aether
  Installed version: 1.0.0
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

```bash
bash tests/run.sh              # everything
bash tests/run.sh gates        # just the gate tests
```

Plain bash and python3, no packages to install. The suite covers dual-mode gate equivalence (each gate behaves identically standalone and under the dispatcher), bypass markers, fail-open on malformed input, install idempotence, migration from a standalone install, and uninstall.

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
