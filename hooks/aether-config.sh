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

aether_cfg_dump() {         # <file> <layer>
  local file="$1" layer="$2"
  [ -f "$file" ] || return 0
  awk -v L="$layer" '
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^\[.*\]$/ { cur = substr($0, 2, length($0) - 2); next }
    {
      line = $0; sub(/^[[:space:]]+/, "", line)
      i = index(line, ":")
      if (i > 1) {
        v = substr(line, i + 1); sub(/^[[:space:]]+/, "", v)
        print L "|" cur "|" substr(line, 1, i - 1) "|" v
      }
    }' "$file"
}

# Idempotent. Call it once per process; every aether_cfg_resolve after that is
# free. Not called implicitly, so a long-lived caller that expects to see edits
# it just made keeps the uncached path.
aether_cfg_preload() {
  AETHER_CFG_ALL="$(aether_cfg_dump "${AETHER_HOME:-$HOME/.aether}/config" global)
$(aether_cfg_dump .aether/config project)"
  AETHER_CFG_PRELOADED=1
}

# Resolve from the preloaded dump: project beats global, per key, with no forks.
_aether_cfg_from_dump() {
  local section="$1" key="$2" line trusted=unknown
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
    if [ "$section" = project ] && [ "$layer" = project ]; then
      [ "$trusted" = unknown ] && { aether_trusted && trusted=yes || trusted=no; }
      [ "$trusted" = yes ] || continue
    fi
    AETHER_CFG_VALUE="${rest#*|}"
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
aether_cfg_resolve() {
  local section="$1" key="$2" val="" v f
  if [ -n "${AETHER_CFG_PRELOADED:-}" ]; then
    _aether_cfg_from_dump "$section" "$key"
    [ -n "$AETHER_CFG_VALUE" ] && return 0
    [ -z "$section" ] && return 0
    # The pre-1.0 files are not in the dump, so they are checked here — but only
    # if they exist. Falling through to the general path instead meant every
    # *unset* key re-read both new files, and most keys are unset, so the cache
    # saved nothing at all.
    f="$HOME/.claude/$section.config"
    if [ -f "$f" ]; then v=$(aether_cfg_read "$f" "" "$key"); [ -n "$v" ] && val="$v"; fi
    f="./$section.config"
    if [ -f "$f" ]; then v=$(aether_cfg_read "$f" "" "$key"); [ -n "$v" ] && val="$v"; fi
    AETHER_CFG_VALUE="$val"
    return 0
  fi
  f="${AETHER_HOME:-$HOME/.aether}/config"
  if [ -f "$f" ]; then v=$(aether_cfg_read "$f" "$section" "$key"); [ -n "$v" ] && val="$v"; fi

  # [project] holds shell commands a critic would execute, so the project layer
  # of that one section waits for `aether trust`. Every other section applies
  # immediately: a threshold cannot run anything.
  if [ "$section" = project ] && ! aether_trusted; then
    AETHER_CFG_VALUE="$val"; return 0
  fi

  if [ -f .aether/config ]; then
    v=$(aether_cfg_read .aether/config "$section" "$key"); [ -n "$v" ] && val="$v"
  fi
  if [ -z "$val" ] && [ -n "$section" ]; then
    f="$HOME/.claude/$section.config"
    if [ -f "$f" ]; then v=$(aether_cfg_read "$f" "" "$key"); [ -n "$v" ] && val="$v"; fi
    f="./$section.config"
    if [ -f "$f" ]; then v=$(aether_cfg_read "$f" "" "$key"); [ -n "$v" ] && val="$v"; fi
  fi
  AETHER_CFG_VALUE="$val"
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
aether_hash_project() {
  local data
  data=$( { cat .aether/config .aether/rules.md 2>/dev/null; } )
  [ -n "$data" ] || { printf 'empty'; return 0; }
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$data" | shasum -a 256 | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$data" | sha256sum | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then
    printf '%s' "$data" | openssl dgst -sha256 | sed 's/^.*= //'
  else
    return 0
  fi
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
