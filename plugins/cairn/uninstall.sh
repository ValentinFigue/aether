#!/bin/bash
# Thin entry point — the engine reads the same manifest in reverse.
# The hand-written uninstallers had drifted from their installers: temper's
# never removed its command files (an undefined $COMMAND_FILE), and cairn's
# never removed the permissions it added.
set -e
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)/bin/aether" uninstall cairn "$@"
