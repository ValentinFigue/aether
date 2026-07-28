#!/usr/bin/env bash
# post-cairn.sh — PostToolUse hook (matcher: Bash|Write|Edit)
#
# Two triggers:
#   1. After temper completes with no blockers → suggest /cairn-commit
#   2. After a version bump in a manifest file → suggest /cairn-changelog
#
# Exit 1 = show nudge.
# Exit 0 = allow silently.

set -euo pipefail

input=$(cat)

result=$(python3 - "$input" <<'PYEOF'
import json, re, sys

data      = json.loads(sys.argv[1])
tool_out  = str(data.get('tool_output', ''))
path      = data.get('tool_input', {}).get('path', '')
content   = (data.get('tool_input', {}).get('new_content', '')
           + data.get('tool_input', {}).get('new_str', ''))

# Trigger 1: temper finished with no blockers
if 'Blockers: 0' in tool_out or 'Good to ship' in tool_out:
    print("post_temper"); sys.exit()

# Trigger 2: version bump in a manifest file
VERSION_FILES = re.compile(
    r'(pyproject\.toml|package\.json|setup\.cfg|Cargo\.toml|'
    r'VERSION|version\.py|__version__)$'
)
VERSION_BUMP = re.compile(r'^\+.*version\s*[=:]\s*["\x27]?\d+\.\d+', re.MULTILINE)

if VERSION_FILES.search(path) and VERSION_BUMP.search(content):
    print("version_bump"); sys.exit()

print("none")
PYEOF
) || exit 0

case "$result" in
  post_temper)
    printf '%s\n' \
      'Cairn: temper found no blockers — ready to commit.' \
      '  /cairn-commit   generates the commit message from your staged diff.'
    exit 1
    ;;
  version_bump)
    printf '%s\n' \
      'Cairn: version bump detected — /cairn-changelog generates the CHANGELOG entry.' \
      '  /cairn-changelog' \
      '  /cairn-changelog --from=<previous-tag> --version=<new-version>'
    exit 1
    ;;
esac

exit 0
