#!/bin/bash
# aether-config.sh — the one config reader.
#
# Sourced by bin/aether and by every gate in <root>/hooks/gates/. Gates run from
# the install directory and cannot reach into the clone, so the engine copies
# this file beside them. Before this existed there were six independent parsers
# of the same format, and two of the four were missing `head -1`, so a
# duplicated key resolved to a multi-line value in half the suite.
#
# Read-only by design: a hook should never write config.

aether_root()      { [ "$1" = global ] && printf '%s' "${AETHER_HOME:-$HOME/.aether}" || printf '.aether'; }
aether_cfg_file()  { printf '%s/config' "$(aether_root "$1")"; }
aether_rules_file(){ printf '%s/rules.md' "$(aether_root "$1")"; }

# Output goes to the project when it has a .aether/, else the global root —
# mirroring what whetstone and temper already did with .claude/plans/.
aether_out_dir() {
  [ -d .aether ] && printf '.aether/out' || printf '%s/out' "$(aether_root global)"
}

# One file per scope with a [section] per plugin, replacing four <plugin>.config
# files per scope. Resolution is per KEY, not per file or per section: a project
# that sets one key does not discard the global value of its neighbours.
#
# Old <plugin>.config files are still READ when the new file has no value, so
# nothing breaks before migration. Writes only ever go to the new location, so
# the two cannot diverge.

# ── Preloading ───────────────────────────────────────────────────────────────
# One awk per config file, once, instead of one per key looked up.
#
# The PreToolUse hook resolves `enabled` for every plugin plus four temper
# thresholds — twelve reads, and so twelve awk processes, on every Bash, Write
# and Edit. That cost nothing before this release only because there was no
# config file to read; seeding a starter config at install made the path
# always-on and took the hook from 81ms to 101ms. Reading both files once and
# answering from a shell variable brings it back.
#
# Format: layer|section|key|value. The layer is kept because [project] from the
# project layer is gated on trust, and a merged view could not tell the two apart.

# <file> <layer> [section]
# The section argument is for the pre-1.0 <plugin>.config files, which have no
# section headers: the filename was the section.
aether_cfg_dump() {
  local file="$1" layer="$2" forced="${3:-}"
  [ -f "$file" ] || return 0
  awk -v L="$layer" -v FORCED="$forced" '
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^\[.*\]$/ {
      cur = substr($0, 2, length($0) - 2)
      # A path area written [project:./web] or [project:web/] is the same area as
      # [project:web]; normalise here so three spellings cannot behave differently.
      if (cur ~ /^project:/) {
        p = substr(cur, 9)
        sub(/^\.\//, "", p); sub(/\/+$/, "", p)
        cur = (p == "" ? "project" : "project:" p)
      }
      next
    }
    {
      line = $0; sub(/^[[:space:]]+/, "", line)
      i = index(line, ":")
      if (i > 1) {
        v = substr(line, i + 1); sub(/^[[:space:]]+/, "", v)
        print L "|" (FORCED != "" ? FORCED : cur) "|" substr(line, 1, i - 1) "|" v
      }
    }' "$file"
}

# Idempotent. Call it once per process; every aether_cfg_resolve after that is
# free. Not called implicitly, so a long-lived caller that expects to see edits
# it just made keeps the uncached path.
# Layers in ascending precedence. The pre-1.0 files sit below the new ones, which
# is equivalent to the old "only read them if the new files had nothing" rule:
# either way a value in a new file wins, and with nothing in the new files the
# project's old file beats the global one.
#
# The legacy names are a hardcoded list on purpose — unlike the plugin list, this
# set is closed history and can never grow, and globbing *.config in the working
# directory would parse whatever a project happens to have lying there.
AETHER_LEGACY_SECTIONS="whetstone bonsai temper cairn trellis"

aether_cfg_preload() {
  local sec
  AETHER_CFG_ALL="$(
    for sec in $AETHER_LEGACY_SECTIONS; do
      aether_cfg_dump "$HOME/.claude/$sec.config" legacy-global "$sec"
    done
    for sec in $AETHER_LEGACY_SECTIONS; do
      aether_cfg_dump "./$sec.config" legacy-project "$sec"
    done
    aether_cfg_dump "${AETHER_HOME:-$HOME/.aether}/config" global
    aether_cfg_dump .aether/config project
  )"
  AETHER_CFG_PRELOADED=1
}

# Anything that writes config invalidates the dump, so a single process that sets
# a key and then reads it back cannot see a stale value.
aether_cfg_invalidate() { unset AETHER_CFG_PRELOADED AETHER_CFG_ALL; }

# Resolve from the preloaded dump: project beats global, per key, with no forks.
_aether_cfg_from_dump() {
  local section="$1" key="$2" line trusted=unknown won="" _gated=""
  AETHER_CFG_VALUE=""
  while IFS= read -r line; do
    case "$line" in
      *"|$section|$key|"*) ;;
      *) continue ;;
    esac
    local layer="${line%%|*}" rest="${line#*|}"
    [ "${rest%%|*}" = "$section" ] || continue
    rest="${rest#*|}"
    [ "${rest%%|*}" = "$key" ] || continue
    # `project` AND every `project:<path>` area. This was an equality test, so a
    # path section bypassed trust entirely and returned its commands from an
    # untrusted repo — harmless only while nothing read them, and `aether check`
    # is exactly something that reads them.
    case "$section" in project|project:*) _gated=1 ;; *) _gated="" ;; esac
    if [ -n "$_gated" ] && [ "$layer" = project ]; then
      [ "$trusted" = unknown ] && { aether_trusted && trusted=yes || trusted=no; }
      [ "$trusted" = yes ] || continue
    fi
    # First occurrence wins *within* a layer — the same rule `head -1` gave, and
    # what a duplicated key in one file has always meant. A higher layer still
    # overrides a lower one, because the dump is emitted in ascending precedence.
    if [ "$layer" != "$won" ]; then
      AETHER_CFG_VALUE="${rest#*|}"; won="$layer"
    fi
  done <<EOF
$AETHER_CFG_ALL
EOF
}

# aether_cfg_read <file> <section> <key>  — one value from one file
aether_cfg_read() {
  local file="$1" section="$2" key="$3"
  [ -f "$file" ] || return 0
  awk -v sec="$section" -v k="$key" '
    { sub(/\r$/, "") }            # a CRLF file must not read as an empty one
    /^[[:space:]]*#/ { next }
    /^\[.*\]$/ { cur = substr($0, 2, length($0) - 2); next }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (index(line, k ":") == 1 && (cur == sec || (sec == "" && cur == ""))) {
        v = substr(line, length(k) + 2)
        sub(/^[[:space:]]+/, "", v)
        print v; exit
      }
    }' "$file"
}

# aether_cfg_get <section> <key> — global, then project, then the pre-1.0 fallback
# Every `$( )` here is a fork, and this runs four times per PreToolUse hook — once
# per plugin, for `enabled`. The first version built each path with a command
# substitution and read every layer unconditionally: ~40 forks per tool call even
# on a machine with no config files at all, which took the hook from 81ms to
# 130ms. Paths are now expanded inline and a layer is only read if its file
# exists, so the common case (nothing configured) forks nothing.
# Resolves into $AETHER_CFG_VALUE and prints nothing, so a caller does not need
# `$( )` — which forks. The PreToolUse hook reads five keys per invocation and
# runs on every Bash, Write and Edit, so those forks were the whole difference
# between 80ms and 130ms per tool call. aether_cfg_get wraps this for the CLI and
# the slash commands, where one fork does not matter.
# One path, always through the dump. There were two — a cached one and an
# uncached one — each implementing layer precedence and the [project] trust gate
# separately, which is exactly the shape that drifts. Preloading on first use
# costs one awk per existing config file, once per process.
aether_cfg_resolve() {
  [ -n "${AETHER_CFG_PRELOADED:-}" ] || aether_cfg_preload
  _aether_cfg_from_dump "$1" "$2"
}

aether_cfg_get() { aether_cfg_resolve "$@"; printf '%s' "$AETHER_CFG_VALUE"; }

# aether_cfg_lineno <file> <section> <key> — where a value came from, so
# `aether config show` can point at the line the user needs to edit.
aether_cfg_lineno() {
  local file="$1" section="$2" key="$3"
  [ -f "$file" ] || return 0
  awk -v sec="$section" -v k="$key" '
    { sub(/\r$/, "") }            # a CRLF file must not read as an empty one
    /^[[:space:]]*#/ { next }
    /^\[.*\]$/ { cur = substr($0, 2, length($0) - 2); next }
    {
      line = $0; sub(/^[[:space:]]+/, "", line)
      if (index(line, k ":") == 1 && (cur == sec || (sec == "" && cur == ""))) { print NR; exit }
    }' "$file"
}

# aether_cfg_keys <file> — every "section|key" a file actually sets. Used by
# `aether config doctor` to find keys no plugin declares, which are otherwise
# silently ignored: the default applies and there is nothing to grep for.
aether_cfg_keys() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^\[.*\]$/ { cur = substr($0, 2, length($0) - 2); next }
    {
      line = $0; sub(/^[[:space:]]+/, "", line)
      i = index(line, ":")
      if (i > 1) print cur "|" substr(line, 1, i - 1)
    }' "$file"
}

# ── Trust ────────────────────────────────────────────────────────────────────
# direnv's model. A project's config can set thresholds and pick critics the
# moment you clone it — none of that can execute anything. Two things can, and
# both wait for consent:
#
#   [project] run-commands   a critic would run them
#   rules.md prose           it reaches a critic's context, which is an
#                            injection vector with no log
#
# Global config and global prose are always trusted: you wrote them.

aether_trust_file() { printf '%s/trusted' "$(aether_root global)"; }

# Content hash of everything a project can say to us.
#
# Deliberately no cksum fallback. cksum is CRC32, and the whole point of the hash
# is that an edit cannot pass for the version you approved — a 32-bit checksum is
# cheap to collide, so someone able to change a trusted repo's config could keep
# the checksum and keep the trust. Returning empty here fails CLOSED: the project
# reads as untrusted, which loses a feature rather than the guarantee.
# aether_sha — SHA-256 of stdin, or nothing.
#
# Deliberately no cksum fallback. cksum is CRC32, and the point of every hash here is
# that an edit cannot pass for the version that was approved — a 32-bit checksum is
# cheap to collide. Printing nothing fails CLOSED: the caller reads it as untrusted or
# uncritiqued, which loses a feature rather than the guarantee.
aether_sha() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 | sed 's/^.*= //'
  else return 0; fi
}

# Content hash of everything a project can say to us.
aether_hash_project() {
  local data
  data=$( { cat .aether/config .aether/rules.md 2>/dev/null; } )
  [ -n "$data" ] || { printf 'empty'; return 0; }
  printf '%s' "$data" | aether_sha
}

# none — never trusted, or nothing to trust
# ok   — trusted, and unchanged since
# changed — trusted once, and edited since. Re-prompt LOUDLY: silently
#           downgrading to global would hide the fact that something changed.
aether_trust_state() {
  [ -f .aether/config ] || [ -f .aether/rules.md ] || { printf 'none'; return 0; }
  # Cheapest check first: with no trust file there is nothing to compare against,
  # so there is no reason to hash anything.
  local f recorded here
  f="${AETHER_HOME:-$HOME/.aether}/trusted"
  [ -f "$f" ] || { printf 'none'; return 0; }
  [ -n "$(aether_hash_project)" ] || { printf 'nohash'; return 0; }
  here=$(pwd -P)
  recorded=$(awk -v p="$here" '{ i = index($0, " "); if (substr($0, i + 1) == p) { print substr($0, 1, i - 1); exit } }' "$f")
  [ -n "$recorded" ] || { printf 'none'; return 0; }
  [ "$recorded" = "$(aether_hash_project)" ] && printf 'ok' || printf 'changed'
}

aether_trusted() { [ "$(aether_trust_state)" = ok ]; }

# Prose for the critics: global first, then the project, each labelled so a
# critic can tell house style from repo specifics. Concatenates rather than
# overriding — losing your global writing rules because a repo added one line
# would be the wrong default.
#
# When the project is untrusted its prose is withheld and that is stated in the
# output, so the critic can say so in its report rather than quietly using less
# context than the user expects.
aether_rules() {
  local g p
  g="$(aether_root global)/rules.md"
  [ -f "$g" ] && { printf '<!-- aether: global rules (~/.aether/rules.md) -->\n'; cat "$g"; printf '\n'; }
  p=".aether/rules.md"
  [ -f "$p" ] || return 0
  case "$(aether_trust_state)" in
    ok) printf '<!-- aether: project rules (.aether/rules.md) -->\n'; cat "$p"; printf '\n' ;;
    changed)
      printf '<!-- aether: project rules.md CHANGED since it was trusted and was NOT read.\n'
      printf '     Say so in the report header. Review the diff, then: aether trust -->\n' ;;
    *)
      printf '<!-- aether: project rules.md exists but is untrusted and was NOT read.\n'
      printf '     Say so in the report header. Review it, then: aether trust -->\n' ;;
  esac
}

# aether_trust_entries — one "state<TAB>path" line per recorded project.
#
#   ok       trusted, and unchanged since
#   changed  trusted once, edited since — its commands and prose are being ignored
#   dead     the directory no longer exists
#
# `dead` is the one nothing used to report. Entries accumulate for every project
# ever trusted, so a path deleted months ago still grants consent if a directory
# is ever recreated there — and there was no way to see that from the outside.
aether_trust_entries() {
  local f line h p state
  f="${AETHER_HOME:-$HOME/.aether}/trusted"
  [ -f "$f" ] || return 0
  while IFS= read -r line; do
    case "$line" in ''|' '*) continue ;; esac
    h="${line%% *}"; p="${line#* }"
    # A line with no space is malformed; skip rather than treat the hash as a path.
    [ -n "$p" ] && [ "$p" != "$line" ] || continue
    if [ ! -d "$p" ]; then
      state=dead
    else
      # Subshell, so a doctor run does not change the caller's directory.
      state=$( cd "$p" 2>/dev/null && { [ "$(aether_hash_project)" = "$h" ] \
                 && printf ok || printf changed; } )
      [ -n "$state" ] || state=dead
    fi
    printf '%s\t%s\n' "$state" "$p"
  done < "$f"
}

# ── Plans ────────────────────────────────────────────────────────────────────
# The critique of a plan lives inside the plan, behind a marker carrying the hash
# of the plan with that marker's block removed. Three reasons, all of which the
# previous mtime-and-separate-file design got wrong:
#
#   - plan mode permits writing only the plan file, so nothing else CAN be written
#   - it is per plan, where one CRITIQUE.md per project meant critiquing plan A
#     satisfied the gate for plan B
#   - a hash survives `touch`, a copy and a checkout, where mtimes do not
#
# The marker:
#   <!-- aether:critique sha=<hex> date=<iso> blockers=<n> -->
#   …the critique…
#   <!-- /aether:critique -->
#
# The block is closed rather than running to end of file. Truncating at the opening
# marker would mean a section appended to the plan AFTER a critique read as part of
# that critique — new, uncritiqued content passing as reviewed. With a close tag the
# hash covers everything outside the block, so appending anywhere makes it stale.

AETHER_PLAN_MARKER='<!-- aether:critique'
AETHER_PLAN_MARKER_END='<!-- /aether:critique -->'

# Project-relative, unconditionally — NOT via aether_out_dir, which falls back to
# ~/.aether/out for a project with no .aether/. That fallback is right for generated
# reports and wrong here: it would make one project's plan pointer global and let the
# first project to record one speak for every other. Exactly the bug the .nudged
# sentinel had before v1.1.0.
aether_plan_pointer() { printf '.aether/out/.plan'; }

# The plan this project is working on: whatever was last written to a plans directory
# while in it, recorded by post-whetstone.sh. Falling back to the pre-1.4 rule — newest
# .md in ./.claude/plans/ — so a project that has not written a plan through the hook
# yet behaves as it always did rather than suddenly going quiet or loud.
aether_plan_file() {
  local ptr f
  ptr=$(aether_plan_pointer)
  if [ -f "$ptr" ]; then
    f=$(head -1 "$ptr" 2>/dev/null)
    [ -n "$f" ] && [ -f "$f" ] && { printf '%s' "$f"; return 0; }
  fi
  ls -t .claude/plans/*.md 2>/dev/null | while IFS= read -r f; do
    case "$(basename "$f")" in CRITIQUE.md|TEMPER.md|.*) continue ;; esac
    printf '%s' "$f"; break
  done
}

# Hash of the plan with its critique block excised — the whole file, not just the part
# above the marker, or an edit made below it would read as current.
aether_plan_hash() {
  [ -f "${1:-}" ] || return 0
  # An unclosed block (hand-edited, or written by something older) is treated as
  # running to end of file, so it degrades to the truncating behaviour rather than
  # hashing a critique into the plan and calling every plan stale.
  # Trailing blank lines are dropped before hashing. Appending the critique block
  # naturally puts a blank line before it, and that blank line is plan content by
  # position — so without this, correctly critiquing a plan made it read as stale.
  # Whitespace at the end of a file is not something a reader would call a change,
  # and fragility of exactly this kind is what the hash replaces.
  awk -v m="$AETHER_PLAN_MARKER" -v e="$AETHER_PLAN_MARKER_END" '
    index($0, m) == 1 { skip = 1; next }
    skip && index($0, e) == 1 { skip = 0; next }
    !skip { l[++n] = $0 }
    END { while (n > 0 && l[n] ~ /^[[:space:]]*$/) n--
          for (i = 1; i <= n; i++) print l[i] }' "$1" | aether_sha
}

# none | uncritiqued | stale | critiqued
aether_plan_state() {
  local f="${1:-}" recorded computed
  [ -n "$f" ] && [ -f "$f" ] || { printf 'none'; return 0; }
  recorded=$(sed -n 's/^<!-- aether:critique .*sha=\([0-9a-f][0-9a-f]*\).*/\1/p' "$f" 2>/dev/null | head -1)
  # A marker with no sha= reads as uncritiqued rather than passing.
  [ -n "$recorded" ] || { printf 'uncritiqued'; return 0; }
  computed=$(aether_plan_hash "$f")
  # No SHA-256 on this machine: nothing can be verified, so nothing is trusted.
  [ -n "$computed" ] || { printf 'uncritiqued'; return 0; }
  [ "$recorded" = "$computed" ] && printf 'critiqued' || printf 'stale'
}


# ── Command parsing ──────────────────────────────────────────────────────────
# One interpreter per hook run, instead of one per gate.
#
# Traced with `bash -x`, a `git commit` used to start three python processes — this
# parse, temper's rule and cairn's rule — plus five greps for the bypass markers. At
# ~18ms per interpreter that was over half the hook's 92ms, paid on every Bash, Write
# and Edit of every session.
#
# Everything a gate used to re-derive is computed once and exported, so a gate becomes
# bash policy over variables rather than a program that re-reads the command. Exported
# rather than printed: a caller that had to read this would fork to do it.

aether_parse_command() {
  [ -n "${AETHER_PARSED:-}" ] && return 0
  local input="${1:-}"
  [ -n "$input" ] || return 1
  eval "$(printf '%s' "$input" | python3 -c 'import json, re, shlex, sys

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(1)
tool = data.get("tool_name", "") or ""
inp = data.get("tool_input") or {}
cmd = inp.get("command") or inp.get("file_path") or inp.get("path") or ""
if not isinstance(cmd, str):
    cmd = ""

# A bypass marker only counts inside a trailing comment: a "#" that begins a word and
# is outside quotes. Grepping the whole command meant a commit *documenting* the
# marker silenced the suite -- an easy accident and a false negative at once.
def comment_of(s):
    in_s = in_d = False
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and not in_s:
            i += 2
            continue
        if c == "'\''" and not in_d:
            in_s = not in_s
        elif c == '\''"'\'' and not in_s:
            in_d = not in_d
        elif c == "#" and not in_s and not in_d and (i == 0 or s[i - 1].isspace()):
            return s[i:]
        i += 1
    return ""

# ...and only in the *trailing* run of marker tokens. `# temper:skip && rm -rf /`
# is a comment containing the marker, not a command marked to be skipped; reading
# it as one would let any text that happens to end up in a comment turn the suite
# off downstream of the word it appears in.
MARKER = re.compile(r"^(?:aether|suite|whetstone|bonsai|temper|cairn):skip$")
markers = []
for tok in reversed(comment_of(cmd).lstrip("#").split()):
    if not MARKER.match(tok):
        break
    markers.append(tok)

IS_PUSH = bool(re.search(r"\bgit\b.*\bpush\b", cmd))
IS_COMMIT = bool(re.search(r"\bgit\b.*\bcommit\b", cmd))
IS_DRY = bool(re.search(r"--dry-run|-n\b", cmd))

msg, has_inline = "", False
if IS_COMMIT:
    has_inline = bool(re.search(r"(-m|--message)\s*.+", cmd))
    m = re.search(r"(?:-m|--message)\s*(?:\"([^\"]+)\"|'\''([^'\'']+)'\''|(\S+))", cmd)
    if m:
        msg = (m.group(1) or m.group(2) or m.group(3) or "").strip()
    else:
        has_inline = False

out = {
    "AETHER_TOOL": tool,
    "AETHER_CMD": cmd,
    "AETHER_IS_COMMIT": "1" if IS_COMMIT else "",
    "AETHER_IS_PUSH": "1" if IS_PUSH else "",
    "AETHER_IS_DRY_RUN": "1" if IS_DRY else "",
    "AETHER_COMMIT_MSG": msg,
    "AETHER_HAS_INLINE_MSG": "1" if has_inline else "",
    "AETHER_IS_SOURCE": "1" if re.search(r"\.(py|ts|tsx|js|jsx|mjs)$", cmd) else "",
    "AETHER_BYPASS": " ".join(sorted(set(markers))),
}
for k, v in out.items():
    print("%s=%s" % (k, shlex.quote(v)))
' 2>/dev/null)" || return 1
  [ -n "${AETHER_TOOL:-}" ] || return 1
  # The names the gates have always used, so nothing downstream has to change.
  tool_name="$AETHER_TOOL"
  cmd_or_path="$AETHER_CMD"
  AETHER_PARSED=1
  return 0
}

# Is this plugin bypassed for this command? One answer for all five call sites, which
# had already drifted: `#\s*`, `# *` and `#[[:space:]]*` in three different gates.
aether_bypassed() {
  case " ${AETHER_BYPASS:-} " in
    *" aether:skip "*|*" suite:skip "*) return 0 ;;
    *" $1:skip "*) return 0 ;;
  esac
  return 1
}

# ── Suppressed nudges ────────────────────────────────────────────────────────
# Where the dispatcher parks the nudges its budget did not print, so
# `aether status --notes` can show them.
#
# Project-relative and never via aether_out_dir, which falls back to
# ~/.aether/out for a project with no .aether/ — that fallback is how v1.1.0's
# once-per-project nudge became once-per-machine and how v1.4.0's plan pointer
# nearly did. State that belongs to one repository is written inside it or not
# at all; prints nothing when there is no .aether/ to put it in.
aether_notes_file() {
  [ -d .aether ] || return 0
  printf '.aether/out/.notes'
}
