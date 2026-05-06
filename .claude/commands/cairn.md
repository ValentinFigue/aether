Parse $ARGUMENTS for flags. Supported flags:
- `--style=conventional` (default) — output a Conventional Commits message (type(scope): description)
- `--style=plain` — output a plain imperative-mood message with no type prefix
- `--off` — print "cairn disabled for this run." and stop

If `--off` is present, print "cairn disabled for this run." and stop immediately.

Resolve style: if `--style=plain` is in $ARGUMENTS use plain, otherwise default to conventional.

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

Analyse the diff and produce a commit message using the style resolved in Step 1.

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
