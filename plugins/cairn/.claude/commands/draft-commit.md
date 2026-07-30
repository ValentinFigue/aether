Draft a commit message from the staged diff (cairn).

Parse $ARGUMENTS for flags. Supported flags:
- `--style=conventional` (default) — output a Conventional Commits message (type(scope): description)
- `--style=plain` — output a plain imperative-mood message with no type prefix
- `--off` — print "cairn disabled for this run." and stop

If `--off` is present in $ARGUMENTS, print "cairn disabled for this run." and stop immediately.

---

**Step 0 — Config check**

Run this single Bash command and capture its output:

```bash
aether config show cairn --raw 2>/dev/null || true
```

Each line is `key: value`, already resolved: global `~/.aether/config`, then the
project's `.aether/config`, per key, with declared defaults filled in. There is
no merging left for you to do.

- If `enabled` is `false`, print `cairn is disabled. Run \`aether cairn enable\` to re-enable.` and stop immediately.
- If the command printed nothing (aether is not installed, or is older than 1.1),
  fall back to the documented defaults and continue — never fail on this step.

Run `aether config show cairn` without `--raw` to see what each key does, where
its current value came from, and which command reads it.

Also resolve `style` from config (used as fallback in Step 3):
- Check local config for `style:` key, then global config.
- Store the resolved config style for use if no `--style` flag is present in $ARGUMENTS.

---

**Step 1 — Read staged diff**

Run `git diff --staged` using the Bash tool. If the output is empty, tell the user "Nothing staged. Run `git add` first." and stop.

**Step 2 — Secrets check**

Scan the diff output for any of these patterns:
- `sk-` (OpenAI / Stripe keys)
- `AKIA` (AWS access key prefix)
- `ghp_` or `ghs_` (GitHub tokens)
- `-----BEGIN` (PEM private keys)
- strings matching `[a-zA-Z0-9]{32,}` inside lines starting with `+` that look like credentials (high-entropy strings next to words like `key`, `token`, `secret`, `password`, `api_key`)

If any pattern is found, print a warning block before continuing:

```
⚠️  Possible secret detected in staged diff. Review before committing:
  <list the matching lines>
Continuing with message generation — no commit will be executed.
```

**Step 3 — Generate commit message**

Resolve style in this priority order:
1. `--style=<x>` in $ARGUMENTS (highest priority)
2. The `style` line from Step 0 — already the resolved project-over-global value
3. Default: `conventional`

Analyse the diff and produce a commit message using the resolved style.

**Conventional style** format:
```
<type>(<scope>): <short description>

<optional body — 1-3 sentences explaining why, not what>

<optional footer — BREAKING CHANGE, closes #issue>
```

Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `build`, `ci`, `perf`

Rules:
- Subject line ≤ 72 characters, imperative mood, no period at end
- Scope is the module/file area affected (omit if change is cross-cutting)
- Body only if the why is non-obvious
- If multiple unrelated areas changed, generate one message per logical group and note they should be separate commits

**Plain style** format:
```
<Short imperative description of what changed>

<optional body>
```

**Step 4 — Output**

Print the commit message(s) in a code block so the user can copy-paste directly into their terminal. Do not run `git commit`. Do not modify any files.

If multiple logical groups were found, print each message in its own block with a label:

```
Commit 1 — <area>:
```git commit -m "..."```

Commit 2 — <area>:
```git commit -m "..."```

Consider splitting this into separate commits.
```
