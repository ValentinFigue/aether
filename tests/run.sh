#!/usr/bin/env bash
# tests/run.sh — run the aether test suite.
#
#   bash tests/run.sh              # everything
#   bash tests/run.sh gates        # only tests/test_gates.sh
#
# No external dependencies: python3 (already required by every hook) and bash.
#
# The files run concurrently and their output is printed in filename order once
# every one has finished, so two runs over the same tree read identically. That
# is safe because every file builds its fixtures under its own throwaway HOME
# and leaves the repo untouched — verified file by file before this stopped
# being a serial loop. Concurrency is the number of test files, not a pool with
# a cap: each file is one single-threaded bash process, so N files cost the
# same total work however they interleave, and the wall clock is the slowest
# file rather than the sum. A capped pool would only add wave-boundary waste
# (bash 3.2 has no `wait -n` to fill a slot the moment it frees).
#
# Per-file times are wall-clock under that concurrency — information, not a
# gate. A file sharing the machine with its neighbours reads slower than it
# would alone.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO" || exit 1

# A local install inside the repo silently corrupts every test. _manifest_get
# prefers the local manifest and resolves it against CWD, not $HOME, so a stray
# .aether/manifest here overrides each test's throwaway HOME — which is
# how `aether status` and `aether update` assertions started reading the
# developer's own install. Fail loudly rather than produce quiet nonsense.
for stray in .aether/manifest .bin/aether .aether/hooks/enforce-suite.sh; do
  if [ -e "$stray" ]; then
    printf '\033[31mrefusing to run: %s exists\033[0m\n' "$stray" >&2
    printf 'A local aether install in this repo overrides the tests fake HOME.\n' >&2
    printf 'Remove it first:  rm -rf .bin .aether/manifest .claude/hooks\n' >&2
    exit 1
  fi
done

filter="${1:-}"

files=() names=()
for f in tests/test_*.sh; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .sh); name=${name#test_}
  if [ -n "$filter" ] && [ "$name" != "$filter" ]; then continue; fi
  files+=("$f"); names+=("$name")
done

if [ "${#files[@]}" -eq 0 ]; then
  printf 'No test files matched %s\n' "${filter:-*}" >&2
  exit 1
fi

logs=$(mktemp -d) || exit 1
trap 'rm -rf "$logs"' EXIT

# Launch first, print later: output order is filename order, not finish order.
# Each job records its own exit code and duration — SECONDS is inherited by the
# subshell and keeps ticking, so the wrapper can time itself; the alternative,
# timing from the parent after `wait`, reports the wall clock at the moment the
# file's turn came, not how long the file took.
pids=()
SECONDS=0
i=0
while [ "$i" -lt "${#files[@]}" ]; do
  ( bash "${files[$i]}" >"$logs/$i.log" 2>&1; echo "$? $SECONDS" >"$logs/$i.done" ) &
  pids[$i]=$!
  i=$((i + 1))
done

# Waiting in launch order only reaps: every job has already written its .done
# by the time its turn comes or waits for itself. Nothing is printed until its
# file has exited, so a log is never half-written.
failed=0
i=0
while [ "$i" -lt "${#files[@]}" ]; do
  wait "${pids[$i]}" 2>/dev/null
  # A wrapper killed before its echo leaves no .done file; count it failed rather
  # than let an empty verdict reach the -eq test and error to stderr.
  read -r verdict secs <"$logs/$i.done" || { verdict=1; secs="?"; }
  printf '\n\033[1m═══ %s ═══\033[0m\n' "${names[$i]}"
  cat "$logs/$i.log"
  if [ "$verdict" -eq 0 ]; then
    printf '\033[32m✓ %s (%ss)\033[0m\n' "${names[$i]}" "$secs"
  else
    failed=$((failed + 1))
    printf '\033[31m✗ %s (%ss)\033[0m\n' "${names[$i]}" "$secs"
  fi
  i=$((i + 1))
done

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32mAll %d test file(s) passed (%ss).\033[0m\n' "${#files[@]}" "$SECONDS"
  exit 0
fi
printf '\033[31m%d of %d test file(s) failed.\033[0m\n' "$failed" "${#files[@]}"
exit 1
