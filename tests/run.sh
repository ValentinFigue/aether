#!/usr/bin/env bash
# tests/run.sh — run the aether test suite.
#
#   bash tests/run.sh              # everything
#   bash tests/run.sh gates        # only tests/test_gates.sh
#
# No external dependencies: python3 (already required by every hook) and bash.

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
failed=0
ran=0

for f in tests/test_*.sh; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .sh); name=${name#test_}
  if [ -n "$filter" ] && [ "$name" != "$filter" ]; then continue; fi
  ran=$((ran + 1))
  printf '\n\033[1m═══ %s ═══\033[0m\n' "$name"
  if ! bash "$f"; then failed=$((failed + 1)); fi
done

if [ "$ran" -eq 0 ]; then
  printf 'No test files matched %s\n' "${filter:-*}" >&2
  exit 1
fi

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32mAll %d test file(s) passed.\033[0m\n' "$ran"
  exit 0
fi
printf '\033[31m%d of %d test file(s) failed.\033[0m\n' "$failed" "$ran"
exit 1
