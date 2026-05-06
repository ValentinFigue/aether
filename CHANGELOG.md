# Changelog

All notable changes to cairn will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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
