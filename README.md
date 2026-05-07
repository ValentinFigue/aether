# aether

Aether binds bonsai, whetstone, temper, and cairn into a single coordinated suite — one install, one bypass convention, one hook that knows the order of things.

---

## Why

Each Claude Code plugin installs its own hook, its own bypass syntax, and touches `settings.json` independently. Install all four and you get four competing hook registrations, redundant gate checks on the same git command, and no shared way to silence them all at once.

Aether solves the wiring problem:

- One `PreToolUse` hook (`enforce-suite.sh`) replaces all four per-plugin hooks
- One `settings.json` pass — no per-plugin editing
- One bypass convention (`# aether:skip`) silences everything; per-plugin markers (`# temper:skip`) work too
- One unified CLAUDE.md block covers all four plugins

The plugins themselves are unchanged — they still install and run standalone.

---

## What it installs

| Plugin | Stage | What it does |
|---|---|---|
| [whetstone](https://github.com/ValentinFigue/whetstone) | Plan | Gates commits when a plan exists but hasn't been critiqued with `/autocritic` |
| [bonsai](https://github.com/ValentinFigue/bonsai) | Build | Nudges toward AST tools (pyrename, tsmove, pyfindrefs) instead of sed/grep/mv on source files |
| [temper](https://github.com/ValentinFigue/temper) | Review | Blocks large/critical commits and pushes until `/temper` has been run |
| [cairn](https://github.com/ValentinFigue/cairn) | Ship | Nudges toward `/cairn-commit`, `/cairn-pr`, and `/cairn-changelog` at every git boundary |

---

## Install

```bash
# Local (this project only)
bash install.sh

# Global (all Claude Code projects)
bash install.sh --global

# With CLAUDE.md rules injected (recommended)
bash install.sh --global --claude-md

# Dry run — see what would happen without making changes
bash install.sh --global --dry-run
```

**curl one-liner (global + CLAUDE.md):**
```bash
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/aether/main/install.sh | bash -s -- --global --claude-md
```

---

## What changes in your environment

| What | Where |
|---|---|
| `enforce-suite.sh` | `~/.local/share/aether/enforce-suite.sh` (global) or `.claude/hooks/enforce-suite.sh` (local) |
| Hook registration | `settings.json` — one `PreToolUse` entry, matcher `Bash\|Write\|Edit\|MultiEdit` |
| Permissions | `settings.json` — `Bash`, `Read`, `Write`, `mcp__bonsai_py__*`, `mcp__bonsai_ts__*` |
| `aether` CLI | `~/.local/bin/aether` |
| CLAUDE.md block | injected with `--claude-md` flag |
| Install manifest | `~/.claude/aether.manifest` |

Per-plugin hooks are removed from `settings.json` during install to avoid duplicates.

---

## The workflow

```
git commit / git push / Write source file
         │
         ▼
  enforce-suite.sh
         │
    ┌────┴────────────────────────────────────────┐
    │                                             │
    ▼                                             ▼
 Bash tool                              Write / Edit / MultiEdit
    │                                             │
    ├─ gate_whetstone                    ├─ gate_whetstone_write
    │  (plan exists, no critique?)       │  (first source write, no critique?)
    │                                   │
    ├─ gate_bonsai                       └─ gate_bonsai
    │  (text tools on source files?)        (text tools on source files?)
    │
    ├─ gate_temper
    │  (large diff? critical path? push?)
    │
    └─ gate_cairn
       (weak commit message? push?)
```

Gates run left to right. Each gate checks `<plugin>.config` for `enabled: false` — a disabled plugin is silently skipped. All gates are non-blocking nudges, except temper which blocks high-risk operations (push without review, critical-path commit).

---

## CLI reference

```
aether status                         Show enabled/disabled state for all plugins + hook state
aether enable  [local|global]         Enable all plugins
aether disable [local|global]         Disable all plugins
aether update                         Update all plugins via git pull (uses install manifest)
aether uninstall [global] [--claude-md]  Remove aether; plugins remain installed standalone
aether help                           Show help
```

**Example output of `aether status`:**

```
aether v1.0.0

  bonsai       enabled  MCP: bonsai-py bonsai-ts
  whetstone    enabled
  temper       enabled
  cairn        enabled

  Suite hook: enforce-suite.sh registered (global)
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

Standalone installs remain fully supported. Each plugin's own `install.sh` works independently. Aether is optional coordination — not a requirement for any single plugin.

```bash
# cairn standalone
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/cairn/main/install.sh | bash -s -- global

# temper standalone
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/temper/main/install.sh | bash -s -- global

# whetstone standalone
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/whetstone/main/install.sh | bash -s -- global

# bonsai standalone (bonsai-py/bonsai-ts not yet on PyPI/npm — install from repo)
# See: https://github.com/valentinfigue/bonsai
git clone https://github.com/valentinfigue/bonsai && cd bonsai && python -m bonsai --install
```

---

## Uninstall

```bash
# Remove suite hook and CLI (plugins remain)
bash uninstall.sh --global

# Also remove CLAUDE.md block
bash uninstall.sh --global --claude-md
```

Or via the CLI: `aether uninstall global --claude-md`

---

## License

MIT
