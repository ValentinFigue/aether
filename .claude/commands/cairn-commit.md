Parse $ARGUMENTS for flags. Supported flags:
- `--style=conventional` (default) — output a Conventional Commits message (type(scope): description)
- `--style=plain` — output a plain imperative-mood message with no type prefix
- `--off` — print "cairn disabled for this run." and stop

If `--off` is present in $ARGUMENTS, print "cairn disabled for this run." and stop immediately.

---

**Step 0 — Config check**

Run this single Bash command and capture its full output:

```bash
{ cat ./cairn.config 2>/dev/null; echo "---CAIRN_SEP---"; cat "$HOME/.claude/cairn.config" 2>/dev/null; }
```

Split the output on the `---CAIRN_SEP---` line. Everything before it is the local config; everything after is the global config. Local takes precedence over global.

Parse both sections for an `enabled:` key:
- If the effective value (local wins if present, otherwise global) is `enabled: false`, print:
  `cairn is disabled. Run \`cairn enable\` to re-enable.`
  and stop immediately.
- If no `enabled:` key is found in either section, default to enabled (continue).

Also resolve `style` from config (used as fallback in Step 3):
- Check local config for `style:` key, then global config.
- Store the resolved config style for use if no `--style` flag is present in $ARGUMENTS.

Note: config values for `enabled` and `style` only contain `true`/`false` or `conventional`/`plain`, so the `---CAIRN_SEP---` separator is safe from false matches.

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
2. `style:` key from local `cairn.config` (read in Step 0)
3. `style:` key from global `cairn.config` (read in Step 0)
4. Default: `conventional`

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
