# Changelog

All notable changes to cairn will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.2.1] — 2026-05-07

### Fixed

- `hooks/enforce-cairn.sh`: replaced `cat <<'MSG'` heredocs with `printf` to prevent bash parse failures caused by CRLF line endings making the closing delimiter unrecognisable (`line 118: unexpected EOF while looking for matching '\''`)
- `hooks/post-cairn.sh`: same heredoc fix; additionally replaced the broken `python3 - <<'PYEOF' ... PYEOF <<< "$input"` pattern — bash treated `<<<` after the delimiter as a new heredoc, cascading a parse error; rewrote to pass JSON input as `sys.argv[1]` (matching the pattern in `enforce-cairn.sh`) and use `json.loads()` accordingly

---

## [0.2.0] — 2026-05-06

### Added

- `/cairn-pr` command: generate PR title and description from branch diff vs base branch; supports `--base`, `--style`, PR template file (`pr.template_file`), and prose rules file (`pr.rules_file`)
- `/cairn-changelog` command: generate a Keep-a-Changelog entry from a commit range; supports `--from`, `--to`, `--version`, `--style`, extra types, and exclude paths
- `/cairn-summary` command: standup/slack/paragraph summary of recent commits; supports `--from`, `--to`, `--format`, and `--author`
- `hooks/enforce-cairn.sh`: PreToolUse hook that nudges toward `/cairn-commit` when a weak `git commit -m` message is detected; supports `# cairn:skip` bypass

### Changed

- `/cairn` renamed to `/cairn-commit` for consistent `cairn-<verb>` naming across all commands
- `cairn-commit.md` now reads `enabled:` from `cairn.config` at runtime — `cairn disable` is now respected by the command itself
- `cairn-commit.md` now reads `style:` from `cairn.config` as fallback when no `--style` flag is passed
- `bin/cairn update` now updates all four installed command files (`cairn-commit.md`, `cairn-pr.md`, `cairn-changelog.md`, `cairn-summary.md`)
- `bin/cairn status` shows install state for all four command files
- `bin/cairn uninstall` removes all four command files and the hook entry
- `bin/cairn config set` supports ten new flags covering per-command settings
- `bin/cairn config show` added: prints effective merged config with source for each key
- `install.sh` installs all four command files, the enforce-cairn hook, and registers the hook in `settings.json` (global mode)
- `uninstall.sh` removes all four command files and the hook registration
- `templates/CLAUDE.md` documentation-sync rule updated to cover all `cairn-*.md` files
- `~/.claude/CLAUDE.md` cairn section updated with per-command trigger guidance
- `~/.claude/CLAUDE.md` now includes a global documentation best-practices rule (applies to all projects)

---

## [0.1.0] — 2026-05-06

### Added

- `/cairn` custom command: reads staged diff and generates a Conventional Commits message
- `--style=conventional` (default) and `--style=plain` flags
- Secrets detection: warns before generating if diff contains `sk-`, `AKIA`, `ghp_`, `ghs_`, or `-----BEGIN` patterns
- Multi-group detection: flags diffs that span unrelated areas and suggests separate commits
- `install.sh`: local and global install modes with `--claude-md` flag for doc rules injection
- `uninstall.sh`: clean removal of command file, CLI binary, and CLAUDE.md section
- `bin/cairn` CLI: `status`, `enable`, `disable`, `config set/reset`, `update`, `uninstall`, `help`
- `templates/CLAUDE.md`: inject-ready documentation sync and changelog rules
- `cairn.config` file format for persistent style preferences (global and local)
