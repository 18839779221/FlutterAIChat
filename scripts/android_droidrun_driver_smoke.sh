#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DROIDRUN_VENV_PATH="${DROIDRUN_VENV_PATH:-/Users/skka/androidSpace/droidrun/.venv}"

cd "${ROOT_DIR}"
"${DROIDRUN_VENV_PATH}/bin/python" scripts/android_droidrun_driver_smoke.py
