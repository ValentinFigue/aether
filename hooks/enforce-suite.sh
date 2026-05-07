#!/usr/bin/env bash
# enforce-suite.sh — aether PreToolUse hook (matcher: Bash|Write|Edit|MultiEdit)
#
# Single coordinated gate chain covering all four suite plugins:
#   whetstone  (plan gate)   — git commit/push when plan exists but no critique
#   bonsai     (AST gate)    — text tools used on source files
#   temper     (review gate) — large/critical git commit; git push; merge/rebase
#   cairn      (ship gate)   — weak commit messages; git push without PR prep
#
# Bypass markers (append as inline bash comment — bash ignores them at runtime):
#   # aether:skip  or  # suite:skip  — silence all gates
#   # whetstone:skip                 — silence whetstone only
#   # bonsai:skip                    — silence bonsai only
#   # temper:skip                    — silence temper only
#   # cairn:skip                     — silence cairn only
#
# Exit 1 = show message (non-blocking nudge, except temper which blocks high-risk ops).
# Exit 0 = allow silently.

set -euo pipefail

# ── Parse stdin ──────────────────────────────────────────────────────────────

input=$(cat)

eval "$(printf '%s' "$input" | python3 -c '
import json, sys, shlex
data = json.loads(sys.stdin.read())
tool = data.get("tool_name", "")
inp  = data.get("tool_input", {})
val  = inp.get("command", "") or inp.get("file_path", "")
print("tool_name=" + shlex.quote(tool))
print("cmd_or_path=" + shlex.quote(val))
' 2>/dev/null)" || exit 0

[ -z "$tool_name" ] && exit 0

# ── Bypass resolution ────────────────────────────────────────────────────────

bypass_all=false
bypass_whetstone=false
bypass_bonsai=false
bypass_temper=false
bypass_cairn=false

printf '%s' "$cmd_or_path" | grep -qE '#[[:space:]]*(aether|suite):skip'    && bypass_all=true
printf '%s' "$cmd_or_path" | grep -qE '#[[:space:]]*whetstone:skip'          && bypass_whetstone=true
printf '%s' "$cmd_or_path" | grep -qE '#[[:space:]]*bonsai:skip'             && bypass_bonsai=true
printf '%s' "$cmd_or_path" | grep -qE '#[[:space:]]*temper:skip'             && bypass_temper=true
printf '%s' "$cmd_or_path" | grep -qE '#[[:space:]]*cairn:skip'              && bypass_cairn=true

$bypass_all && exit 0

# ── Plugin enabled check ─────────────────────────────────────────────────────

_plugin_enabled() {
  local plugin="$1"
  local global_cfg="$HOME/.claude/${plugin}.config"
  local local_cfg="./${plugin}.config"
  local val=""

  [ -f "$global_cfg" ] && val=$(grep "^enabled:" "$global_cfg" | sed "s/^enabled: *//" | head -1) || true
  [ -f "$local_cfg"  ] && {
    local lv
    lv=$(grep "^enabled:" "$local_cfg" | sed "s/^enabled: *//" | head -1 2>/dev/null) || true
    [ -n "$lv" ] && val="$lv"
  } || true

  [ "$val" = "false" ] && return 1
  return 0
}

# ── Gate: whetstone ──────────────────────────────────────────────────────────
# Fires on: git commit, git push (Bash tool)
# Checks:   plan exists without critique, or critique is stale

gate_whetstone() {
  $bypass_whetstone && return 0
  _plugin_enabled whetstone || return 0

  printf '%s' "$cmd_or_path" | grep -qE '^git (push|commit)' || return 0

  local CRITIQUE_FILE=".claude/plans/CRITIQUE.md"

  local plan_file
  plan_file=$(python3 -c '
import os, glob
plans = [f for f in glob.glob(".claude/plans/*.md")
         if os.path.basename(f) not in ("CRITIQUE.md",)
         and not os.path.basename(f).startswith(".")]
print(max(plans, key=os.path.getmtime) if plans else "")
' 2>/dev/null) || return 0

  if [ -n "$plan_file" ] && [ ! -f "$CRITIQUE_FILE" ]; then
    printf 'Whetstone: a plan exists but has not been critiqued yet.\n'
    printf '  Run /autocritic before committing to surface blockers now.\n'
    printf '  Append  # whetstone:skip  to your git command to bypass.\n'
    return 1
  fi

  if [ -n "$plan_file" ] && [ -f "$CRITIQUE_FILE" ]; then
    local stale
    stale=$(python3 -c "
import os
plan = os.path.getmtime('$plan_file')
crit = os.path.getmtime('$CRITIQUE_FILE')
print('stale' if plan > crit else 'ok')
" 2>/dev/null) || return 0
    if [ "$stale" = "stale" ]; then
      printf 'Whetstone: plan was modified after the last critique — critique is stale.\n'
      printf '  Re-run /autocritic on the updated plan before committing.\n'
      printf '  Append  # whetstone:skip  to your git command to bypass.\n'
      return 1
    fi
  fi

  return 0
}

# Whetstone also fires on first source-file write with no critique on record
gate_whetstone_write() {
  $bypass_whetstone && return 0
  _plugin_enabled whetstone || return 0

  printf '%s' "$tool_name" | grep -qE '^(Write|Edit|MultiEdit)$' || return 0

  local is_source
  is_source=$(python3 -c "
import re, sys
print('yes' if re.search(r'\.(py|ts|tsx|js|jsx|mjs)$', sys.argv[1]) else 'no')
" "$cmd_or_path" 2>/dev/null) || return 0

  if [ "$is_source" = "yes" ] && [ ! -f ".claude/plans/CRITIQUE.md" ]; then
    local sentinel=".claude/plans/.whetstone-nudged"
    [ -f "$sentinel" ] && return 0
    mkdir -p ".claude/plans" 2>/dev/null || true
    touch "$sentinel" 2>/dev/null || true
    printf 'Whetstone: writing source code with no critiqued plan on record.\n'
    printf '  If this is a planned change, run /autocritic first.\n'
    printf '  Append  # whetstone:skip  to your path to bypass.\n'
    return 1
  fi

  return 0
}

# ── Gate: bonsai ─────────────────────────────────────────────────────────────
# Fires on: Bash tool with text tools (grep/sed/awk/mv) on source files

gate_bonsai() {
  $bypass_bonsai && return 0
  _plugin_enabled bonsai || return 0

  printf '%s' "$tool_name" | grep -qE '^Bash$' || return 0

  local result
  result=$(python3 - "$cmd_or_path" <<'PYEOF'
import re, sys
cmd = sys.argv[1]

SRC = r'\.(py|ts|tsx|js|jsx|mjs)(\b|$)'

SEARCH_RE = re.compile(r'\b(grep|rg|ripgrep|ag|ack|fgrep)\b')
MUTATE_RE  = re.compile(r'\b(sed|awk|perl)\b')
MOVE_RE    = re.compile(r'\b(mv|git\s+mv|cp)\b')
XARGS_RE   = re.compile(r'\bxargs\b.*(sed|awk|perl)', re.DOTALL)

has_src = bool(re.search(SRC, cmd))

if MOVE_RE.search(cmd) and has_src:
    print("move")
elif (MUTATE_RE.search(cmd) or XARGS_RE.search(cmd)) and has_src:
    print("mutate")
elif SEARCH_RE.search(cmd) and has_src:
    print("search")
else:
    print("none")
PYEOF
  ) || return 0

  case "$result" in
    search)
      printf 'Bonsai nudge — searching source files:\n'
      printf '  grep/rg on .py   →  pyfindrefs <symbol>  or  pygrep <pattern> (AST-aware)\n'
      printf '  grep/rg on .ts   →  tsfindrefs <symbol>  (catches type references grep misses)\n'
      printf '  looking for dead code?  →  pyfindunused\n'
      printf 'Append  # bonsai:skip  if you need raw text search.\n'
      return 1
      ;;
    mutate)
      printf 'Bonsai nudge — mutating source files with a text tool:\n'
      printf '  sed/perl rename  →  pyrename <old> <new>  or  tsrename (safe: updates imports)\n'
      printf '  sed signature    →  pysignature / tssignature (propagates call-site changes)\n'
      printf '  Always dry-run first: pyrename --dry-run <old> <new>\n'
      printf 'Append  # bonsai:skip  if bonsai has no equivalent for your operation.\n'
      return 1
      ;;
    move)
      printf 'Bonsai nudge — moving or copying a source file:\n'
      printf '  mv / git mv .py  →  pymove <src> <dst>   (rewrites all import paths)\n'
      printf '  mv / git mv .ts  →  tsmove <src> <dst>\n'
      printf '  Always dry-run first: pymove --dry-run <src> <dst>\n'
      printf 'Append  # bonsai:skip  if this is a new/untracked file with no importers.\n'
      return 1
      ;;
  esac

  return 0
}

# ── Gate: temper ─────────────────────────────────────────────────────────────
# Fires on: git push, git commit (large/critical), git merge, git rebase -i, git stash pop

gate_temper() {
  $bypass_temper && return 0
  _plugin_enabled temper || return 0

  printf '%s' "$tool_name" | grep -qE '^Bash$' || return 0
  printf '%s' "$cmd_or_path" | grep -qE '^git ' || return 0

  local GLOBAL_CONFIG="$HOME/.claude/temper.config"
  local LOCAL_CONFIG="./temper.config"

  _gate_temper_config() {
    local key="$1" val=""
    [ -f "$GLOBAL_CONFIG" ] && val=$(grep "^$key:" "$GLOBAL_CONFIG" | sed "s/^$key: *//" | head -1) || true
    [ -f "$LOCAL_CONFIG"  ] && { local lv; lv=$(grep "^$key:" "$LOCAL_CONFIG" | sed "s/^$key: *//" | head -1 2>/dev/null) && [ -n "$lv" ] && val="$lv"; } || true
    printf '%s' "$val"
  }

  local auto_nudge_lines auto_nudge_files critical_paths
  auto_nudge_lines=$(_gate_temper_config "auto_nudge_lines"); auto_nudge_lines=${auto_nudge_lines:-200}
  auto_nudge_files=$(_gate_temper_config "auto_nudge_files"); auto_nudge_files=${auto_nudge_files:-10}
  critical_paths=$(_gate_temper_config "critical_paths")
  critical_paths=${critical_paths:-"*auth*|*permission*|*token*|migrations/|*alembic*|\\.sql|*schema*|*secret*|*credential*|\\.env"}

  local _tmppy
  _tmppy=$(mktemp /tmp/temper_suite.XXXXXX.py)
  cat > "$_tmppy" << 'PYEOF'
import re, subprocess, sys, os

cmd = sys.argv[1]
auto_nudge_lines = int(sys.argv[2])
auto_nudge_files = int(sys.argv[3])
critical_paths_raw = sys.argv[4]

def run(args):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=10)
        return r.stdout.strip()
    except Exception:
        return ""

if re.match(r'\bgit\b\s+push\b', cmd):
    if re.search(r'--dry-run|-n\b', cmd):
        print("none"); sys.exit(0)
    print("push"); sys.exit(0)

if re.match(r'\bgit\b\s+commit\b', cmd):
    shortstat = run(["git", "diff", "--staged", "--shortstat"])
    lines = sum(int(x) for x in re.findall(r'(\d+) (?:insertion|deletion)', shortstat))
    files_out = run(["git", "diff", "--staged", "--name-only"])
    files = len([f for f in files_out.splitlines() if f]) if files_out else 0

    if lines > auto_nudge_lines or files > auto_nudge_files:
        print("commit_large"); sys.exit(0)

    patterns = [p.strip().replace("*", ".*") for p in critical_paths_raw.split("|")]
    staged_files = files_out.splitlines() if files_out else []
    for filepath in staged_files:
        for pat in patterns:
            if re.search(pat, filepath, re.IGNORECASE):
                print("commit_critical"); sys.exit(0)

    print("none"); sys.exit(0)

if re.match(r'\bgit\b\s+merge\b', cmd):
    primary = {"main", "master", "develop", "trunk"}
    tokens = [t for t in cmd.split() if not t.startswith("-")]
    branch = tokens[-1] if len(tokens) > 2 else ""
    print("merge_primary" if branch in primary else "none"); sys.exit(0)

if re.match(r'\bgit\b\s+rebase\b.*-i\b', cmd) or re.match(r'\bgit\b\s+rebase\b\s+-i\b', cmd):
    tokens = cmd.split()
    rebase_idx = next((i for i, t in enumerate(tokens) if t == "rebase"), -1)
    ref = None
    for t in tokens[rebase_idx + 1:]:
        if not t.startswith("-"):
            ref = t; break
    if ref is None:
        print("none"); sys.exit(0)
    m = re.match(r'HEAD~(\d+)', ref, re.IGNORECASE)
    if m:
        count = int(m.group(1))
    else:
        out = run(["git", "rev-list", "--count", f"HEAD...{ref}"])
        try: count = int(out)
        except ValueError: count = 0
    print("rebase_large" if count > 5 else "none"); sys.exit(0)

if re.match(r'\bgit\b\s+stash\b.*\bpop\b', cmd):
    stash_diff = run(["git", "stash", "show", "-p", "stash@{0}"])
    lines = len(stash_diff.splitlines()) if stash_diff else 0
    print("stash_large" if lines > auto_nudge_lines else "none"); sys.exit(0)

print("none")
PYEOF

  local result
  result=$(python3 "$_tmppy" "$cmd_or_path" "$auto_nudge_lines" "$auto_nudge_files" "$critical_paths" 2>/dev/null) || { rm -f "$_tmppy"; return 0; }
  rm -f "$_tmppy"

  case "$result" in
    push)
      printf 'temper: about to push — have you run /temper to review your changes?\n'
      printf '  Run /temper first, then push.\n'
      printf '  Append  # temper:skip  (or  # suite:skip) to bypass.\n'
      return 1
      ;;
    commit_large)
      printf 'temper: large commit detected — consider running /temper first.\n'
      printf '  Your staged diff exceeds the size threshold (lines or files).\n'
      printf '  Append  # temper:skip  (or  # suite:skip) to bypass.\n'
      return 1
      ;;
    commit_critical)
      printf 'temper: critical path file detected in staged changes — run /temper first.\n'
      printf '  One or more staged files matches a critical path pattern (auth, schema, migrations).\n'
      printf '  Append  # temper:skip  (or  # suite:skip) to bypass.\n'
      return 1
      ;;
    merge_primary)
      printf 'temper: merging into a primary branch — consider running /temper --diff=all first.\n'
      printf '  Append  # temper:skip  (or  # suite:skip) to bypass.\n'
      return 1
      ;;
    rebase_large)
      printf 'temper: interactive rebase touching many commits — consider /temper --diff=all after.\n'
      printf '  Append  # temper:skip  (or  # suite:skip) to bypass.\n'
      return 1
      ;;
    stash_large)
      printf 'temper: large stash detected — consider running /temper before committing.\n'
      printf '  Append  # temper:skip  (or  # suite:skip) to bypass.\n'
      return 1
      ;;
  esac

  return 0
}

# ── Gate: cairn ──────────────────────────────────────────────────────────────
# Fires on: git commit (weak/missing message), git push

gate_cairn() {
  $bypass_cairn && return 0
  _plugin_enabled cairn || return 0

  printf '%s' "$tool_name" | grep -qE '^Bash$' || return 0

  # Use a temp file to avoid bash misinterpreting single quotes inside $( <<'HEREDOC' )
  local _tmppy
  _tmppy=$(mktemp /tmp/cairn_suite.XXXXXX.py)
  cat > "$_tmppy" << 'PYEOF'
import re, sys
cmd = sys.argv[1]

IS_COMMIT = re.search(r'\bgit\b.*\bcommit\b', cmd)
IS_PUSH   = re.search(r'\bgit\b.*\bpush\b', cmd)

if IS_PUSH:
    if re.search(r'--dry-run|-n\b', cmd):
        print("none"); sys.exit(0)
    print("push"); sys.exit(0)

if IS_COMMIT:
    has_inline_msg = bool(re.search(r'(-m|--message)\s*.+', cmd))
    if not has_inline_msg:
        print("commit_no_message"); sys.exit(0)

    # Match -m "msg", -m 'msg', or -m word
    m = re.search(r"(?:-m|--message)\s*(?:\"([^\"]+)\"" + r"|'([^']+)'|(\S+))", cmd)
    if not m:
        print("commit_no_message"); sys.exit(0)
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
        r'^\w+$',
    ]

    msg_lower = msg.lower().rstrip(".,!")
    is_weak = (
        len(msg) < 12
        or msg_lower in WEAK_SINGLE
        or any(re.match(p, msg_lower) for p in WEAK_PATTERNS)
    )

    is_conventional = bool(re.match(
        r'^(feat|fix|docs|style|refactor|perf|test|chore|ci|build|revert)(\(.+\))?!?: .{10,}',
        msg
    ))

    if is_conventional:
        print("none"); sys.exit(0)
    if is_weak:
        print("commit_weak"); sys.exit(0)

print("none")
PYEOF

  local result
  result=$(python3 "$_tmppy" "$cmd_or_path" 2>/dev/null) || { rm -f "$_tmppy"; return 0; }
  rm -f "$_tmppy"

  case "$result" in
    commit_weak)
      printf 'Cairn nudge: the commit message looks weak — /cairn-commit writes a better one.\n'
      printf '  Stage your changes, then:  /cairn-commit\n'
      printf '  Append  # cairn:skip  to commit with this message anyway.\n'
      return 1
      ;;
    commit_no_message)
      printf 'Cairn nudge: no inline message — /cairn-commit generates one from your staged diff.\n'
      printf '  /cairn-commit\n'
      printf '  Append  # cairn:skip  to open your editor instead.\n'
      return 1
      ;;
    push)
      printf 'Cairn nudge: about to push — /cairn-pr writes the PR title and description.\n'
      printf '  /cairn-pr              (auto-detects base branch)\n'
      printf '  Append  # cairn:skip  to push without a PR description.\n'
      return 1
      ;;
  esac

  return 0
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
# Run gates in pipeline order. Accumulate exit codes; unexpected errors fail open.

_exit=0

{
  if printf '%s' "$tool_name" | grep -qE '^Bash$'; then
    # Bash tool: whetstone → bonsai → temper → cairn
    gate_whetstone || _exit=1
    gate_bonsai    || _exit=1
    gate_temper    || _exit=1
    gate_cairn     || _exit=1
  fi

  if printf '%s' "$tool_name" | grep -qE '^(Write|Edit|MultiEdit)$'; then
    # Write/Edit/MultiEdit tool: whetstone write gate only (bonsai is Bash-only)
    gate_whetstone_write || _exit=1
  fi
} || true

exit $_exit
