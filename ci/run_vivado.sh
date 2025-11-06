#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR=${1:-$SCRIPT_DIR/../out/vivado}

mkdir -p "$BUILD_DIR"
vivado -mode batch -source "$SCRIPT_DIR/../hw/build/vivado_proj.tcl" -tclargs "$BUILD_DIR"
