#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MAKE_FLAGS=${MAKE_FLAGS:-}

pushd "$SCRIPT_DIR/../sw/rtos_demo" >/dev/null
make ${MAKE_FLAGS}
popd >/dev/null
