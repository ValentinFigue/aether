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
