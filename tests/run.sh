#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"

nvim --headless -u tests/minimal_init.lua \
    -c "PlenaryBustedDirectory tests/integration { minimal_init = 'tests/minimal_init.lua' }" \
    "$@"
