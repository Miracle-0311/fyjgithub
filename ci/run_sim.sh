#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SIM_DIR=${SIM_DIR:-$SCRIPT_DIR/../out/sim}
mkdir -p "$SIM_DIR"

# Placeholder for simulation command. Replace with xrun/vcs invocation.
echo "[INFO] Simulation environment not configured. Provide vendor simulator command here." >&2
