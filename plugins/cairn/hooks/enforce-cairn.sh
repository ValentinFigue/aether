#!/usr/bin/env bash
# enforce-cairn.sh — PreToolUse command hook (matcher: Bash)
#
# Three gates:
#   1. git commit with a weak or missing message    → suggest /draft-commit
#   2. git push to a remote                         → suggest /draft-pr
#   3. git commit with no inline -m flag            → suggest /draft-commit
#
# Bypass: append  # cairn:skip  or  # suite:skip  to silence.
# Exit 1 = show nudge (non-blocking).
# Exit 0 = allow silently.
#
# Dual mode. Standalone, the entrypoint at the bottom reads stdin and exits.
# Under the aether suite, enforce-suite.sh sources this file with SUITE_MODE=1
# and calls gate_cairn with $cmd_or_path already parsed — so the gate below is
# the single definition of cairn's rules, not a copy the suite has to mirror.

# ── Message quality ──────────────────────────────────────────────────────────
# A direct port of the python this replaced, kept deliberately literal — same word
# list, same four patterns, same 12-character floor, same conventional-commit
# escape hatch, in the same order. It is a port because it is on the hook's hot
# path: python3 costs ~18ms to start and this rule is a regex plus a set lookup,
# which bash already does. `tests/test_rules.sh` keeps the messages it was
# diffed against, as assertions.
#
# Echoes one of: none | commit_weak
_cairn_judge() {
  local msg="$1" ml

  # Well-formed conventional commit: type(scope): description — never weak.
  # Checked before weakness, as in the original: `fix: <10+ chars>` outranks the
  # fact that "fix" is itself a weak word.
  local conv='^(feat|fix|docs|style|refactor|perf|test|chore|ci|build|revert)(\(.+\))?!?: .{10,}'
  if [[ $msg =~ $conv ]]; then printf none; return 0; fi

  ml=$(printf '%s' "$msg" | tr '[:upper:]' '[:lower:]')
  # python's rstrip(".,!") — strips every trailing character in the set, not one
  while :; do
    case "$ml" in
      *[.,!]) ml="${ml%?}" ;;
      *) break ;;
    esac
  done

  if [ "${#msg}" -lt 12 ]; then printf commit_weak; return 0; fi

  case " fix wip misc update changes stuff test temp tmp commit save done ok patch tweak cleanup refactor work more " in
    *" $ml "*) printf commit_weak; return 0 ;;
  esac

  local p
  for p in \
    '^(fix(ed|es|ing)?|updat(e|ed|ing)|add(s|ed|ing)?)[[:space:]]+(bug|issue|stuff|things?|it|this)$' \
    '^more (changes|fixes|updates|work)$' \
    '^(minor|small|quick)[[:space:]]+[[:alnum:]_]+$' \
    '^[[:alnum:]_]+$'
  do
    if [[ $ml =~ $p ]]; then printf commit_weak; return 0; fi
  done

  printf none
}

# ── Gate ─────────────────────────────────────────────────────────────────────
# Reads: $cmd_or_path.  Returns: 1 to nudge, 0 to stay silent.
gate_cairn() {
  local cmd="${cmd_or_path:-}"
  [ -z "$cmd" ] && return 0
  aether_bypassed cairn && return 0

  local result=none

  # ── Gate 2: git push ───────────────────────────────────────────────────────
  if [ -n "${AETHER_IS_PUSH:-}" ]; then
    # Skip dry-runs — the user is not actually pushing
    [ -n "${AETHER_IS_DRY_RUN:-}" ] && return 0
    result=push

  # ── Gate 1: git commit with weak or missing message ────────────────────────
  elif [ -n "${AETHER_IS_COMMIT:-}" ]; then
    if [ -z "${AETHER_HAS_INLINE_MSG:-}" ]; then
      # No inline -m flag → message will open an editor; cairn is the better path
      result=commit_no_message
    else
      result=$(_cairn_judge "${AETHER_COMMIT_MSG:-}")
    fi
  fi

  case "$result" in
    commit_weak)
      printf '%s\n' \
        'Cairn nudge: the commit message looks weak — /draft-commit writes a better one.' \
        '  Stage your changes, then:  /draft-commit' \
        '  It generates a Conventional Commits message from the actual diff.' \
        '  Paste the result into:  git commit -m "<cairn output>"' \
        '' \
        '  Append  # cairn:skip  to commit with this message anyway.'
      return 1
      ;;
    commit_no_message)
      printf '%s\n' \
        'Cairn nudge: no inline message — /draft-commit generates one from your staged diff.' \
        '  /draft-commit' \
        '  Then:  git commit -m "<cairn output>"' \
        '' \
        '  Append  # cairn:skip  to open your editor instead.'
      return 1
      ;;
    push)
      printf '%s\n' \
        'Cairn nudge: about to push — /draft-pr writes the PR title and description.' \
        '  /draft-pr              (auto-detects base branch)' \
        '  /draft-pr --base=develop' \
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

  _here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
  for _lib in "$_here/../aether-config.sh" "$_here/aether-config.sh" \
              "$_here/../../../hooks/aether-config.sh" \
              "${AETHER_HOME:-$HOME/.aether}/hooks/aether-config.sh"; do
    # shellcheck source=/dev/null
    [ -f "$_lib" ] && { . "$_lib"; break; }
  done
  unset _lib _here
  command -v aether_parse_command >/dev/null 2>&1 || exit 0

  # The same parse the suite runs, so standalone and suite modes cannot drift.
  aether_parse_command "$(cat)" || exit 0

  # Commands only — the old standalone parse read tool_input.command and nothing
  # else, so a Write payload reached the gate empty. The shared parse falls back
  # to file_path; this keeps that difference invisible.
  [ "${AETHER_TOOL:-}" = Bash ] || exit 0

  gate_cairn
  exit $?
fi
