# Changelog

All notable changes to aether are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.1.0] — 2026-05-07

### Added

- `install.sh` — suite installer; registers `enforce-suite.sh` as the single PreToolUse hook and installs bonsai, whetstone, temper, and cairn
- `uninstall.sh` — clean removal of the suite hook, CLI, and optional CLAUDE.md block
- `hooks/enforce-suite.sh` — central dispatch hook; replaces per-plugin hooks with a single coordinated gate chain
- `bin/aether` — CLI for `status`, `update`, `enable`, `disable`, `uninstall`, and `help`
- `templates/CLAUDE.md` — unified CLAUDE.md block covering all four plugins under `<!-- aether:start -->` / `<!-- aether:end -->` sentinels
- `BYPASS.md` — canonical bypass specification; all four plugin READMEs link here
- `CHANGELOG.md` — this file
- `README.md` — full documentation: why, what it installs, install instructions, workflow diagram, CLI reference, and bypass table
