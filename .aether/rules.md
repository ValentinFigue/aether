[all]
This is a bash project, and its own hooks run on every Claude Code tool call.
Two consequences worth applying to every review:

- Prefer POSIX-compatible constructs. CI runs the suite on macOS, which ships
  bash 3.2 — no associative arrays, no `${var,,}`, no `EPOCHREALTIME`. Anything
  that needs bash 4 will pass on Ubuntu and fail on macOS.
- BSD and GNU userland differ in ways that have already cost real bugs here:
  `awk -F` reads an escaped pipe as alternation on BSD, `date` has no `%N`, and
  `timeout` does not exist. Flag any new dependency on GNU-only behaviour.

[critique-diff]
Anything under `hooks/` or `plugins/*/hooks/` runs on every Bash, Write and Edit
in every session. Weigh two things there far above line count:

- **Cost.** A process spawned per key resolved is a process spawned on every tool
  call. Reading a file once and answering from a variable is not a
  micro-optimisation here.
- **Fail-open.** A gate must exit 0 or 1, never 2 — exit 2 blocks the tool call,
  so a malformed gate would lock the user out of every command. Stderr must stay
  empty for the same reason.

`bin/aether` writes to `settings.json`, `~/.claude.json` and `CLAUDE.md`, all of
which belong to Claude Code rather than to us. Any change there should be
idempotent and should back up before its first write.

[critique-pr]
The install and uninstall paths are the highest-risk surface in this repo: they
are what a user cannot easily undo. For any change to them, check that uninstall
still reverses install, and that re-running install twice is a no-op — both have
regressed here before.

[draft-pr]
Never add generation or attribution footers to a PR description — no "Generated
with", no tool name, no bot emoji. The description is about the change, and a
reader looking for why the code is the way it is does not need to be told what
typed it.

[draft-commit]
Explain the mechanism, not the symptom. "X was broken, now fixed" is not useful;
say what the code did, why that produced the observed behaviour, and why the fix
addresses the cause. Bugs that produced plausible output rather than an error are
worth saying so explicitly, because those are the ones tests miss.

Never add attribution trailers — no `Co-Authored-By`, no "Generated with", no tool
name. `[git] trailers` is empty for the same reason, so if a trailer appears, it did
not come from this project's convention.
