#!/usr/bin/env bash
# enforce-bonsai.sh — PreToolUse hook (matcher: Bash)
#
# Intercepts two categories:
#   1. Text tools used on source files  (grep, sed, awk, find, rg, ag, perl, xargs)
#   2. File move/rename operations      (mv, git mv, cp)
#
# Bypass: append  # bonsai:skip  or  # suite:skip  to silence for that command.
# Bash treats it as a comment and ignores it at runtime.
# Exit 1 = allow the command but show the nudge as informational context.
# Exit 0 = allow silently.
#
# Dual mode. Standalone, the entrypoint at the bottom reads stdin and exits.
# Under the aether suite, enforce-suite.sh sources this file with SUITE_MODE=1
# and calls gate_bonsai with $cmd_or_path already parsed.

# ── Gate ─────────────────────────────────────────────────────────────────────
# Reads: $cmd_or_path.  Returns: 1 to nudge, 0 to stay silent.
gate_bonsai() {
  local cmd="${cmd_or_path:-}"
  [ -z "$cmd" ] && return 0

  # Bypass marker
  aether_bypassed bonsai && return 0

  # Classify the command into one of three operation types.
  #
  # A direct port of the python this replaced — same four categories, same
  # precedence, same source extensions. python3 costs ~18ms to start and this is
  # four regexes; on a hook that fires on every Bash call that was the second of
  # three interpreters. `\b` has no POSIX ERE equivalent, so it is written out as
  # "not a word character, or the edge of the string". `tests/test_rules.sh` keeps
  # the commands it was diffed against, as assertions.
  local W='[^[:alnum:]_]'
  local SRC="\.(py|ts|tsx|js|jsx|mjs)($W|$)"
  [[ $cmd =~ $SRC ]] || return 0

  local SEARCH="(^|$W)(grep|rg|ripgrep|ag|ack|pygrep|fgrep)($W|\$)"
  local MUTATE="(^|$W)(sed|awk|perl)($W|\$)"
  local MOVE="(^|$W)(mv|git[[:space:]]+mv|cp)($W|\$)"
  local XARGS="(^|$W)xargs($W|\$).*(sed|awk|perl)"

  local result=none
  if [[ $cmd =~ $MOVE ]]; then
    result=move
  elif [[ $cmd =~ $MUTATE ]] || [[ $cmd =~ $XARGS ]]; then
    result=mutate
  elif [[ $cmd =~ $SEARCH ]]; then
    result=search
  fi

  case "$result" in
    search)
      cat <<'MSG'
Bonsai nudge — searching source files:
  grep/rg on .py   →  pyfindrefs <symbol>  or  pygrep <pattern> (AST-aware, follows re-exports)
  grep/rg on .ts   →  tsfindrefs <symbol>  (catches type references grep misses)
  looking for dead code?  →  pyfindunused
Append  # bonsai:skip  if you need raw text search.
MSG
      return 1
      ;;
    mutate)
      cat <<'MSG'
Bonsai nudge — mutating source files with a text tool:
  sed/perl rename  →  pyrename <old> <new>  or  tsrename (safe: updates imports, types, re-exports)
  sed signature    →  pysignature / tssignature (propagates call-site changes)
  Text substitution silently breaks aliased imports and type references.
  Always dry-run first: pyrename --dry-run <old> <new>
Append  # bonsai:skip  if bonsai has no equivalent for your operation.
MSG
      return 1
      ;;
    move)
      cat <<'MSG'
Bonsai nudge — moving or copying a source file:
  mv / git mv .py  →  pymove <src> <dst>   (rewrites all import paths automatically)
  mv / git mv .ts  →  tsmove <src> <dst>
  Raw mv leaves all import statements pointing at the old path.
  Always dry-run first: pymove --dry-run <src> <dst>
Append  # bonsai:skip  if this is a new/untracked file with no importers.
MSG
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

# ── Standalone entrypoint ────────────────────────────────────────────────────
# Skipped when sourced by enforce-suite.sh. `set -e` lives here rather than at
# file scope so sourcing cannot change the caller's shell options.
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

  # bonsai reads commands only. Its old standalone parse read tool_input.command
  # and nothing else, so a Write payload reached the gate as an empty string; the
  # shared parse falls back to file_path, and this keeps that difference invisible.
  [ "${AETHER_TOOL:-}" = Bash ] || exit 0

  gate_bonsai
  exit $?
fi
