# cairn

**Mark where you've been.** Cairn reads your diff, understands the intent behind the changes, and writes your commit messages — so the trail is always readable.

No dependencies. No MCP server. No build step.

---

## Why

Git history is a graveyard of `fix`, `wip`, and `misc`.

Not because the work was unclear — because writing a good commit message after finishing a feature takes context you've already moved past. `/cairn` reads what you actually changed and writes the message for you: semantic, conventional, and ready to paste.

---

## Install

**Recommended — global, available in every project:**

```bash
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/cairn/main/install.sh | bash -s global
```

This installs the `/cairn` command, the `cairn` CLI to `~/.local/bin/`, and configures the required `Bash`, `Read`, and `Write` permissions in `~/.claude/settings.json` so git diff runs without permission prompts.

**With documentation rules** — also injects project behaviour rules into `~/.claude/CLAUDE.md`:

```bash
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/cairn/main/install.sh | bash -s global --claude-md
```

**Local only** — available in this project only:

```bash
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/cairn/main/install.sh | bash
```

**Manual one-liner** (no script):

```bash
# Global
mkdir -p ~/.claude/commands
curl -fsSL -o ~/.claude/commands/cairn.md \
  https://raw.githubusercontent.com/ValentinFigue/cairn/main/.claude/commands/cairn.md

# Local
mkdir -p .claude/commands
curl -fsSL -o .claude/commands/cairn.md \
  https://raw.githubusercontent.com/ValentinFigue/cairn/main/.claude/commands/cairn.md
```

If installing manually, add `"Bash"`, `"Read"`, and `"Write"` to `permissions.allow` in the relevant `settings.json` to avoid prompts when cairn reads the staged diff.

Restart Claude Code. The `/cairn` command is immediately available.

**To uninstall:**

```bash
# Global
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/cairn/main/uninstall.sh | bash -s global --claude-md

# Local
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/cairn/main/uninstall.sh | bash
```

---

## Usage

Stage your changes, then run `/cairn` in Claude Code:

```
git add src/auth/token.py
/cairn
```

Cairn reads the staged diff and generates a commit message. The output is always copy-paste ready — cairn never runs `git commit` for you.

---

## Quick reference

| Command | What it does |
|---|---|
| `/cairn` | Generate a Conventional Commits message from staged diff |
| `/cairn --style=plain` | Plain imperative-mood message, no type prefix |
| `/cairn --style=conventional` | Explicit conventional style (default) |
| `/cairn --off` | Skip this run |

---

## What you get

```
feat(auth): add token expiry validation on login

Tokens were accepted past their expiry window when the clock skew
tolerance was set above 30s. Adds a hard ceiling regardless of tolerance.

Closes #412
```

If your staged diff spans multiple unrelated areas, cairn flags it and suggests separate commits:

```
Commit 1 — auth:
git commit -m "feat(auth): add token expiry validation on login"

Commit 2 — docs:
git commit -m "docs: update token lifecycle diagram"

Consider splitting this into separate commits.
```

Cairn also warns before generating if it detects common secret patterns in your diff — API keys, tokens, or PEM blocks staged by accident.

---

## Configuration

Cairn resolves settings in three layers, lowest to highest priority:

**1. Global config** (`~/.claude/cairn.config`) — your personal defaults across all projects  
**2. Local config** (`./cairn.config`) — project-level overrides  
**3. Per-run flags** (`$ARGUMENTS`) — always win, override both config files

Config file format:

```
enabled: true
style: conventional
```

---

## cairn CLI

A global install also provides a `cairn` command for managing your setup:

```bash
cairn status                              # install state + effective config

cairn disable local                       # silence for this project
cairn disable global                      # silence everywhere
cairn enable local                        # restore

cairn config set --style=plain            # plain style for this project
cairn config set --style=conventional --global  # conventional everywhere
cairn config reset local                  # wipe project overrides

cairn update                              # pull latest cairn.md
cairn uninstall global --claude-md        # full removal
```

Run `cairn help` for the full reference.

---

## Roadmap

Planned for future versions — contributions welcome:

- [ ] `/cairn-pr` — generate a full PR title and description from the branch diff vs base
- [ ] `/cairn-changelog` — generate a CHANGELOG entry from a commit range
- [ ] `/cairn-summary` — plain-language standup summary of what changed and why
- [ ] `cairn.config` support for commit style, extra conventional types, and exclude paths
- [ ] `cairn disable` / `enable` respected by the command file at runtime
- [ ] MCP server upgrade for richer git integration

---

## Works well with

[**bonsai**](https://github.com/ValentinFigue/bonsai) — AST-powered refactoring for Claude Code. Bonsai makes the cuts; cairn records them.

[**whetstone**](https://github.com/ValentinFigue/whetstone) — Plan critic. Whetstone sharpens the plan before you build; cairn narrates what you built.

---

## License

MIT — see [LICENSE](LICENSE).
