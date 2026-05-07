# Changelog

## [0.1.1] — 2026-05-07

### Added
- `# suite:skip` bypass token — silences all suite hooks (temper, cairn, whetstone) with one annotation
- Curl one-liner install pattern in README and install.sh tips output

### Changed
- Hook entry is now prepended (not appended) in `settings.json` so temper fires before cairn on `git commit`
- `settings.json` mutation is now wrapped in `flock` when available, guarding against concurrent suite installs

### Fixed
- Bypass regex updated to `# *(temper|suite):skip` — both tokens handled consistently across all hook messages

---

## [0.1.0] — 2026-05-06

Initial release.

### Added
- `/temper` command: four-critic diff review (Correctness, Design, Risk, Coverage)
- Config resolution: 3-layer (global → local → flags), identical to whetstone/cairn conventions
- Diff targeting: staged (default), unstaged, all, commit-ish, with empty-staging fallback
- Secrets scan: warns on known credential patterns before critiquing
- Output persistence: appends to `.claude/plans/TEMPER.md` with date headers
- Severity gate: blocks push on 🔴 findings, single bypass via `# temper:skip`
- `enforce-temper.sh` hook: blocks `git push` (always), `git commit` (size/critical-path threshold), `git merge` (primary branches), `git rebase -i` (>5 commits), `git stash pop` (size threshold)
- `templates/CLAUDE.md`: proactive Tier 1 rules for session scope awareness, critical path detection, and post-bonsai gate
- `bin/temper` CLI: status, enable/disable, config set/get/reset, update, uninstall
- `install.sh` / `uninstall.sh`: local and global install modes, `--claude-md` flag for proactive injection, Python/Node/jq fallback chain for settings.json mutation
