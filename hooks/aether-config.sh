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

# aether_cfg_read <file> <section> <key>  — one value from one file
aether_cfg_read() {
  local file="$1" section="$2" key="$3"
  [ -f "$file" ] || return 0
  awk -v sec="$section" -v k="$key" '
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
aether_cfg_get() {
  local section="$1" key="$2" val=""
  local g; g=$(aether_cfg_read "$(aether_cfg_file global)" "$section" "$key"); [ -n "$g" ] && val="$g"
  local l; l=$(aether_cfg_read "$(aether_cfg_file local)"  "$section" "$key"); [ -n "$l" ] && val="$l"
  if [ -z "$val" ] && [ -n "$section" ]; then
    local og ol
    og=$(aether_cfg_read "$HOME/.claude/$section.config" "" "$key"); [ -n "$og" ] && val="$og"
    ol=$(aether_cfg_read "./$section.config"             "" "$key"); [ -n "$ol" ] && val="$ol"
  fi
  printf '%s' "$val"
}

# aether_cfg_lineno <file> <section> <key> — where a value came from, so
# `aether config show` can point at the line the user needs to edit.
aether_cfg_lineno() {
  local file="$1" section="$2" key="$3"
  [ -f "$file" ] || return 0
  awk -v sec="$section" -v k="$key" '
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
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^\[.*\]$/ { cur = substr($0, 2, length($0) - 2); next }
    {
      line = $0; sub(/^[[:space:]]+/, "", line)
      i = index(line, ":")
      if (i > 1) print cur "|" substr(line, 1, i - 1)
    }' "$file"
}
