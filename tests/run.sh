#!/usr/bin/env bash
# tests/run.sh — run the aether test suite.
#
#   bash tests/run.sh              # everything, test files run in parallel
#   bash tests/run.sh gates        # only tests/test_gates.sh
#   AETHER_TEST_JOBS=1 bash tests/run.sh   # serial: one file at a time, streamed
#
# No external dependencies: python3 (already required by every hook) and bash.
#
# The files are independent — each builds its own throwaway HOME and fixture
# repos, and the repo itself is only read — so they are safe to run side by
# side. That matters because the suite's cost is process spawns (thousands of
# short-lived bash/awk/python3), not memory or network: wall time scales with
# concurrency until the slowest single file is the floor. Parallelism is
# bounded by core count. Each file's output is captured to a temp file and
# replayed in glob order once the run ends, with one progress line printed as
# each file finishes; AETHER_TEST_JOBS=1 restores the old serial streaming.

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

files=()
names=()
for f in tests/test_*.sh; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .sh); name=${name#test_}
  if [ -n "$filter" ] && [ "$name" != "$filter" ]; then continue; fi
  files+=("$f")
  names+=("$name")
done

if [ "${#files[@]}" -eq 0 ]; then
  printf 'No test files matched %s\n' "${filter:-*}" >&2
  exit 1
fi

run_serial() {
  local i
  for ((i = 0; i < ${#files[@]}; i++)); do
    printf '\n\033[1m═══ %s ═══\033[0m\n' "${names[$i]}"
    if ! bash "${files[$i]}"; then failed=$((failed + 1)); fi
  done
}

run_parallel() { # <concurrency>
  local j="$1" i b rc tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/aether-run.XXXXXXXX")
  trap "rm -rf '$tmp'" EXIT
  trap "rm -rf '$tmp'; exit 130" INT TERM
  printf '%s\n' "${files[@]}" | xargs -P "$j" -n 1 bash -c '
    tmp="$1"; f="$2"; b="${f##*/}"
    s=$SECONDS
    if bash "$f" > "$tmp/$b.log" 2>&1; then rc=0; else rc=1; fi
    printf "%s\n" "$rc" > "$tmp/$b.rc"
    if [ "$rc" -eq 0 ]; then
      printf "\033[32m  ✓ %s (%ss)\033[0m\n" "$b" "$((SECONDS - s))"
    else
      printf "\033[31m  ✗ %s (%ss)\033[0m\n" "$b" "$((SECONDS - s))"
    fi
  ' _ "$tmp"
  for ((i = 0; i < ${#files[@]}; i++)); do
    b=$(basename "${files[$i]}")
    rc=$(cat "$tmp/$b.rc" 2>/dev/null || echo 1)
    printf '\n\033[1m═══ %s ═══\033[0m\n' "${names[$i]}"
    cat "$tmp/$b.log"
    [ "$rc" = "0" ] || failed=$((failed + 1))
  done
  rm -rf "$tmp"
}

cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
jobs=${AETHER_TEST_JOBS:-$cores}
case "$jobs" in (*[!0-9]*|"") jobs=$cores ;; esac
[ "$jobs" -ge 1 ] 2>/dev/null || jobs=1
if [ "$jobs" -gt "${#files[@]}" ]; then jobs=${#files[@]}; fi

failed=0
if [ "$jobs" -eq 1 ]; then
  run_serial
else
  run_parallel "$jobs"
fi

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32mAll %d test file(s) passed.\033[0m\n' "${#files[@]}"
  exit 0
fi
printf '\033[31m%d of %d test file(s) failed.\033[0m\n' "$failed" "${#files[@]}"
exit 1
