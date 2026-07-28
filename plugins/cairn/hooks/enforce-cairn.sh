#!/usr/bin/env bash
# enforce-cairn.sh — PreToolUse command hook (matcher: Bash)
#
# Three gates:
#   1. git commit with a weak or missing message    → suggest /cairn-commit
#   2. git push to a remote                         → suggest /cairn-pr
#   3. git commit with no inline -m flag            → suggest /cairn-commit
#
# Bypass: append  # cairn:skip  or  # suite:skip  to silence.
# Exit 1 = show nudge (non-blocking).
# Exit 0 = allow silently.
#
# Dual mode. Standalone, the entrypoint at the bottom reads stdin and exits.
# Under the aether suite, enforce-suite.sh sources this file with SUITE_MODE=1
# and calls gate_cairn with $cmd_or_path already parsed — so the gate below is
# the single definition of cairn's rules, not a copy the suite has to mirror.

# ── Gate ─────────────────────────────────────────────────────────────────────
# Reads: $cmd_or_path.  Returns: 1 to nudge, 0 to stay silent.
gate_cairn() {
  local cmd="${cmd_or_path:-}"
  [ -z "$cmd" ] && return 0

  # Bypass markers
  if printf '%s' "$cmd" | grep -qE '# *(cairn|suite):skip'; then
    return 0
  fi

  local result
  result=$(python3 - "$cmd" <<'PYEOF'
import re, sys
cmd = sys.argv[1]

IS_COMMIT = re.search(r'\bgit\b.*\bcommit\b', cmd)
IS_PUSH   = re.search(r'\bgit\b.*\bpush\b', cmd)

# ── Gate 2: git push ─────────────────────────────────────────────────────────
if IS_PUSH:
    # Skip dry-runs — the user is not actually pushing
    if re.search(r'--dry-run|-n\b', cmd):
        print("none"); sys.exit()
    print("push"); sys.exit()

# ── Gate 1: git commit with weak or missing message ──────────────────────────
if IS_COMMIT:
    # No inline -m flag → message will open an editor; cairn is the better path
    has_inline_msg = bool(re.search(r'(-m|--message)\s*.+', cmd))
    if not has_inline_msg:
        print("commit_no_message"); sys.exit()

    # Extract the inline message.
    # Apostrophes are written \x27 rather than \' on purpose: bash tracks quote
    # state through a heredoc body when scanning $( ... ) for its closing paren,
    # so an odd number of single quotes here breaks the whole command
    # substitution with "syntax error near unexpected token )".
    m = re.search(r"(?:-m|--message)\s*(?:\"([^\"]+)\"|\x27([^\x27]+)\x27|(\S+))", cmd)
    if not m:
        print("commit_no_message"); sys.exit()
    msg = (m.group(1) or m.group(2) or m.group(3) or "").strip()

    WEAK_SINGLE = {
        "fix", "wip", "misc", "update", "changes", "stuff",
        "test", "temp", "tmp", "commit", "save", "done", "ok",
        "patch", "tweak", "cleanup", "refactor", "work", "more",
    }
    WEAK_PATTERNS = [
        r'^(fix(ed|es|ing)?|updat(e|ed|ing)|add(s|ed|ing)?)\s+(bug|issue|stuff|things?|it|this)$',
        r'^more (changes|fixes|updates|work)$',
        r'^(minor|small|quick)\s+\w+$',
        r'^\w+$',              # single word, no conventional prefix
    ]

    msg_lower = msg.lower().rstrip(".,!")
    is_weak = (
        len(msg) < 12
        or msg_lower in WEAK_SINGLE
        or any(re.match(p, msg_lower) for p in WEAK_PATTERNS)
    )

    # Well-formed conventional commit: type(scope): description  — never weak
    is_conventional = bool(re.match(
        r'^(feat|fix|docs|style|refactor|perf|test|chore|ci|build|revert)(\(.+\))?!?: .{10,}',
        msg
    ))

    if is_conventional:
        print("none"); sys.exit()

    if is_weak:
        print("commit_weak"); sys.exit()

    print("none"); sys.exit()

print("none")
PYEOF
) || return 0

  case "$result" in
    commit_weak)
      printf '%s\n' \
        'Cairn nudge: the commit message looks weak — /cairn-commit writes a better one.' \
        '  Stage your changes, then:  /cairn-commit' \
        '  It generates a Conventional Commits message from the actual diff.' \
        '  Paste the result into:  git commit -m "<cairn output>"' \
        '' \
        '  Append  # cairn:skip  to commit with this message anyway.'
      return 1
      ;;
    commit_no_message)
      printf '%s\n' \
        'Cairn nudge: no inline message — /cairn-commit generates one from your staged diff.' \
        '  /cairn-commit' \
        '  Then:  git commit -m "<cairn output>"' \
        '' \
        '  Append  # cairn:skip  to open your editor instead.'
      return 1
      ;;
    push)
      printf '%s\n' \
        'Cairn nudge: about to push — /cairn-pr writes the PR title and description.' \
        '  /cairn-pr              (auto-detects base branch)' \
        '  /cairn-pr --base=develop' \
        '' \
        '  Append  # cairn:skip  to push without a PR description.'
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

# ── Standalone entrypoint ────────────────────────────────────────────────────
# Skipped when sourced by enforce-suite.sh, which owns stdin parsing and the
# exit code. `set -e` lives here rather than at file scope so sourcing cannot
# change the caller's shell options.
if [ -z "${SUITE_MODE:-}" ]; then
  set -euo pipefail

  input=$(cat)

  cmd_or_path=$(printf '%s' "$input" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('command', ''))
" 2>/dev/null) || exit 0

  gate_cairn
  exit $?
fi
