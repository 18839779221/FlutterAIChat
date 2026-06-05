#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

output="$(bash "$ROOT_DIR/scripts/ios_install_release.sh" --help 2>&1 || true)"

if [[ "$output" != *"Usage: bash scripts/ios_install_release.sh"* ]]; then
  echo "Expected usage output from ios_install_release.sh"
  echo "$output"
  exit 1
fi

if [[ "$output" != *"--no-launch"* ]]; then
  echo "Expected --no-launch option to be documented"
  echo "$output"
  exit 1
fi
