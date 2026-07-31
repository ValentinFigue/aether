#!/usr/bin/env bash
# enforce-temper.sh — PreToolUse command hook (matcher: Bash)
#
# Calls out high-risk git operations and nudges the agent to run /critique-diff first.
# This is Tier 2 (reactive). The proactive Tier 1 rules live in templates/CLAUDE.md.
#
# Triggers:
#   git push *        — always (except --dry-run)
#   git commit *      — if staged diff exceeds size threshold or touches critical paths
#   git merge *       — if merging into a primary branch (main/master/develop/trunk)
#   git rebase -i *   — if rebase range exceeds 5 commits
#   git stash pop *   — if stash diff exceeds size threshold
#
# Bypass: append  # temper:skip  (or  # suite:skip) as a trailing comment. The marker is
# only honoured there — see BYPASS.md.
#
# Exit 1 = show the message. Exit 0 = stay silent. Neither stops the command: only exit 2
# does that in Claude Code, and no aether hook ever exits 2, because one corrupt gate file
# would then lock the user out of every command. `tests/acceptance.sh` asserts it.
#
# Internally the gate returns 2 for its two high-risk verdicts (unreviewed push,
# critical-path commit) so enforce-suite.sh's nudge budget can tell them from advice and
# never suppress them. The standalone entrypoint clamps that back to 1.
#
# Dual mode. Standalone, the entrypoint at the bottom reads stdin and exits.
# Under the aether suite, enforce-suite.sh sources this file with SUITE_MODE=1
# and calls gate_temper with $cmd_or_path already parsed.

# ── Config reader ────────────────────────────────────────────────────────────
# One parser, shared with bin/aether. Under the suite it is already sourced by
# enforce-suite.sh; standalone this finds it. A gate that cannot find it must
# still run — every config key has a default, so the gate degrades to those
# rather than going silent.
if ! command -v aether_cfg_get >/dev/null 2>&1; then
  _ac_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
  for _ac in "$_ac_here/../aether-config.sh" "$_ac_here/aether-config.sh" \
             "$_ac_here/../../../hooks/aether-config.sh" \
             "${AETHER_HOME:-$HOME/.aether}/hooks/aether-config.sh"; do
    [ -f "$_ac" ] && { . "$_ac"; break; }
  done
  unset _ac _ac_here
  if ! command -v aether_cfg_get >/dev/null 2>&1; then
    aether_cfg_get() { :; }
    aether_out_dir() { [ -d .aether ] && printf '.aether/out' || printf '%s/out' "${AETHER_HOME:-$HOME/.aether}"; }
  fi
fi

# Namespaced: several plugin hooks are sourced into one shell under the suite,
# so a bare _config_get would collide.
# Assigns rather than prints, for the same reason _plugin_enabled does: the gate
# reads four keys and runs on every Bash call.
_temper_cfg() {
  if command -v aether_cfg_resolve >/dev/null 2>&1; then aether_cfg_resolve temper "$1"
  else AETHER_CFG_VALUE=""; fi
}

# ── Rule helpers ─────────────────────────────────────────────────────────────
# A direct port of the python this replaced. It is a port because it sat on the
# hook's hot path: python3 costs ~18ms to start, and every branch below is git
# plus arithmetic — which git and awk already do. `tests/test_rules.sh` keeps the
# repository states it was diffed against, as assertions.
#
# The python used `re.match`, which anchors at position 0, so `echo hi && git push`
# never matched. Preserved deliberately: cairn's `re.search` and temper's `re.match`
# genuinely differ on that command, and this change is not the place to reconcile
# them. `^git[[:space:]]+` is what `re.match(r'\bgit\b\s+')` reduces to — `\b` at
# position 0 only succeeds when the first character is a word character.
_tp_word_end='([^[:alnum:]_]|$)'

# reviewed | no | unknown, via the CLI so there is one implementation of the answer.
# Falls back to `no` only when the CLI is absent entirely — an install too old to know
# about reviews behaves exactly as it did before.
_temper_review_state() {
  local a out=""
  for a in "$HOME/.local/bin/aether" aether; do
    command -v "$a" >/dev/null 2>&1 && { out=$("$a" review status --raw 2>/dev/null); break; }
  done
  # Validate rather than trust. An install predating `aether review` prints its usage
  # error here, and an unrecognised string must not be read as evidence of anything —
  # it lands on `unknown`, which nudges exactly as this gate did before reviews existed.
  case "$out" in
    reviewed|no|unknown) printf '%s' "$out" ;;
    *)                   printf 'unknown' ;;
  esac
}

# Sum of insertions and deletions in the staged diff — python's
# re.findall(r'(\d+) (?:insertion|deletion)', shortstat), summed.
_temper_staged_lines() {
  git diff --staged --shortstat 2>/dev/null | awk '
    { for (i = 2; i <= NF; i++) if ($i ~ /^insertion|^deletion/) s += $(i-1) }
    END { print s + 0 }'
}

# Build one extended regex from the pipe-separated patterns, matching python:
# each pattern is stripped, then "*" becomes ".*", then searched case-insensitively.
# Empty patterns are kept rather than skipped — in python an empty pattern matches
# every path, and a rewrite that quietly fixed that would not be a no-op.
_temper_critical_ere() {
  local raw="$1" p out="" first=1 oldifs="$IFS"
  IFS='|'
  for p in $raw; do
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    if [ "$first" = 1 ]; then out="${p//\*/.*}"; first=0
    else out="$out|${p//\*/.*}"; fi
  done
  IFS="$oldifs"
  printf '%s' "$out"
}

# ── Gate ─────────────────────────────────────────────────────────────────────
# Reads: $cmd_or_path.  Returns: 1 to nudge, 0 to stay silent.
gate_temper() {
  local cmd="${cmd_or_path:-}"
  [ -z "$cmd" ] && return 0
  aether_bypassed temper && return 0

  local enabled auto_nudge_lines auto_nudge_files critical_paths result=none
  _temper_cfg enabled; enabled="$AETHER_CFG_VALUE"
  if [ "$enabled" = "false" ]; then
    return 0
  fi

  _temper_cfg auto_nudge_lines; auto_nudge_lines="$AETHER_CFG_VALUE"
  auto_nudge_lines=${auto_nudge_lines:-200}
  _temper_cfg auto_nudge_files; auto_nudge_files="$AETHER_CFG_VALUE"
  auto_nudge_files=${auto_nudge_files:-10}
  _temper_cfg critical_paths; critical_paths="$AETHER_CFG_VALUE"
  critical_paths=${critical_paths:-"*auth*|*permission*|*token*|migrations/|*alembic*|\\.sql|*schema*|*secret*|*credential*|\\.env"}

  # ── git push ───────────────────────────────────────────────────────────────
  if [[ $cmd =~ ^git[[:space:]]+push$_tp_word_end ]]; then
    # Allow dry-run passes through
    [ -n "${AETHER_IS_DRY_RUN:-}" ] && return 0
    # Consult the review record. This used to fire unconditionally, which is tolerable
    # as a nudge and useless as anything stronger — a verdict that is always the same
    # carries no information. `unknown` (no sha256 tool, no .aether/, no base branch)
    # is not a soft no: the question could not be answered, so nothing is claimed.
    case "$(_temper_review_state)" in
      reviewed) return 0 ;;
      unknown)  result=push_unknown ;;
      *)        result=push ;;
    esac

  # ── git commit ─────────────────────────────────────────────────────────────
  elif [[ $cmd =~ ^git[[:space:]]+commit$_tp_word_end ]]; then
    local lines files
    lines=$(_temper_staged_lines)
    files=$(git diff --staged --name-only 2>/dev/null | awk '$0 != "" { n++ } END { print n + 0 }')

    if [ "$lines" -gt "$auto_nudge_lines" ] || [ "$files" -gt "$auto_nudge_files" ]; then
      result=commit_large
    elif git diff --staged --name-only 2>/dev/null \
         | grep -qiE "$(_temper_critical_ere "$critical_paths")"; then
      result=commit_critical
    fi

  # ── git merge ──────────────────────────────────────────────────────────────
  elif [[ $cmd =~ ^git[[:space:]]+merge$_tp_word_end ]]; then
    # The branch is the last non-flag token, and only when there is one beyond
    # `git merge` itself — a bare `git merge` names no branch.
    # read -ra rather than word-splitting $cmd: unquoted expansion would glob, and
    # `git merge *` must be tokens, not a directory listing.
    local t branch="" n=0 IFS=$' \t\n'
    local -a toks; read -ra toks <<< "$cmd"
    for t in "${toks[@]}"; do
      case "$t" in -*) ;; *) branch="$t"; n=$((n + 1)) ;; esac
    done
    [ "$n" -gt 2 ] || branch=""
    case "$branch" in
      main|master|develop|trunk) result=merge_primary ;;
    esac

  # ── git rebase -i ──────────────────────────────────────────────────────────
  elif [[ $cmd =~ ^git[[:space:]]+rebase$_tp_word_end.*-i$_tp_word_end ]]; then
    local t ref="" seen=0 count=0 IFS=$' \t\n'
    local -a toks; read -ra toks <<< "$cmd"
    for t in "${toks[@]}"; do
      if [ "$seen" = 1 ]; then
        case "$t" in -*) ;; *) ref="$t"; break ;; esac
      fi
      [ "$t" = rebase ] && seen=1
    done
    if [ -n "$ref" ]; then
      # HEAD~N is answerable without asking git; anything else needs rev-list.
      if [[ $ref =~ ^[Hh][Ee][Aa][Dd]~([0-9]+) ]]; then
        count="${BASH_REMATCH[1]}"
      else
        count=$(git rev-list --count "HEAD...$ref" 2>/dev/null)
        case "$count" in ''|*[!0-9]*) count=0 ;; esac
      fi
      [ "$count" -gt 5 ] && result=rebase_large
    fi

  # ── git stash pop ──────────────────────────────────────────────────────────
  elif [[ $cmd =~ ^git[[:space:]]+stash$_tp_word_end.*pop$_tp_word_end ]]; then
    local lines
    lines=$(git stash show -p 'stash@{0}' 2>/dev/null | awk 'END { print NR + 0 }')
    [ "$lines" -gt "$auto_nudge_lines" ] && result=stash_large
  fi

  case "$result" in
    push_unknown)
      cat <<'MSG'
temper: about to push — have you run /critique-diff to review your changes?
  Whether this branch has been reviewed could not be determined here.
  Append  # temper:skip  (or  # suite:skip) to your push command to bypass this check.
MSG
      return 1   # advisory: nothing is known, so nothing is escalated
      ;;
    push)
      cat <<'MSG'
temper: about to push — have you run /critique-diff to review your changes?
  Run /critique-diff first, then push.
  Append  # temper:skip  (or  # suite:skip) to your push command to bypass this check.
MSG
      return 2   # block, not advice — never budgeted away
      ;;
    commit_large)
      cat <<'MSG'
temper: large commit detected — consider running /critique-diff first.
  Your staged diff exceeds the size threshold (lines or files).
  Append  # temper:skip  (or  # suite:skip) to your commit command to bypass this check.
MSG
      return 1
      ;;
    commit_critical)
      cat <<'MSG'
temper: critical path file detected in staged changes — run /critique-diff first.
  One or more staged files matches a critical path pattern (auth, schema, migrations, credentials).
  Append  # temper:skip  (or  # suite:skip) to your commit command to bypass this check.
MSG
      return 2   # block, not advice — never budgeted away
      ;;
    merge_primary)
      cat <<'MSG'
temper: merging into a primary branch — consider running /critique-diff --diff=all first.
  Merges into main/master/develop/trunk have high surface area.
  Append  # temper:skip  (or  # suite:skip) to your merge command to bypass this check.
MSG
      return 1
      ;;
    rebase_large)
      cat <<'MSG'
temper: interactive rebase touching many commits — consider /critique-diff --diff=all after.
  Append  # temper:skip  (or  # suite:skip) to your rebase command to bypass this check.
MSG
      return 1
      ;;
    stash_large)
      cat <<'MSG'
temper: large stash detected — consider running /critique-diff before committing.
  Your stash exceeds the size threshold. Apply it, then run /critique-diff before committing.
  Append  # temper:skip  (or  # suite:skip) to your stash pop command to bypass this check.
MSG
      return 1
      ;;
  esac

  return 0
}

# ── Standalone entrypoint ────────────────────────────────────────────────────
# Skipped when sourced by enforce-suite.sh. `set -e` lives here rather than at
# file scope so sourcing cannot change the caller's shell options.
if [ -z "${SUITE_MODE:-}" ]; then
  set -euo pipefail

  command -v aether_parse_command >/dev/null 2>&1 || exit 0
  # The same parse the suite runs, so standalone and suite modes cannot drift.
  aether_parse_command "$(cat)" || exit 0

  # Standalone, a block and a nudge are both exit 1: the gate contract is 0 or 1
  # and never 2, which Claude Code reads as "block the tool call". The severity
  # only exists so the dispatcher's budget can tell them apart.
  # Commands only — the old standalone parse read tool_input.command and nothing
  # else, so a Write payload reached the gate empty. The shared parse falls back
  # to file_path; this keeps that difference invisible.
  [ "${AETHER_TOOL:-}" = Bash ] || exit 0

  gate_temper && exit 0
  exit 1
fi
