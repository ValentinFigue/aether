#!/bin/bash
# Thin entry point — the engine installs whetstone from plugins/whetstone/aether.plugin.
# aether is installed alongside, so there is one engine on the machine rather
# than five installers that had drifted apart.
set -e
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)/bin/aether" install whetstone "$@"
