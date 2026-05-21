#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_FLUTTER_VERSION="3.35.7"
APK_PATH="$ROOT_DIR/build/app/outputs/flutter-apk/app-debug.apk"

usage() {
  cat <<'EOF'
Usage: bash scripts/android_install_debug.sh [device_id]

Builds the latest debug APK and installs it to an Android device using
adb overwrite install (-r -t) only. It does not fall back to uninstall.

Arguments:
  device_id    Optional Android device serial. If omitted and exactly one
               physical device is connected, that device is used.
EOF
}

resolve_flutter_cmd() {
  local flutter_version
  flutter_version="$(flutter --version 2>/dev/null | head -n 1 || true)"
  if [[ "$flutter_version" == *"$EXPECTED_FLUTTER_VERSION"* ]]; then
    echo "flutter"
    return
  fi

  if command -v fvm >/dev/null 2>&1; then
    echo "fvm flutter"
    return
  fi

  echo "flutter"
}

resolve_device_id() {
  local requested_device="${1:-}"
  if [[ -n "$requested_device" ]]; then
    echo "$requested_device"
    return
  fi

  if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    echo "$ANDROID_SERIAL"
    return
  fi

  local devices=()
  while IFS= read -r device; do
    if [[ -n "$device" ]]; then
      devices+=("$device")
    fi
  done < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')

  if [[ "${#devices[@]}" -eq 1 ]]; then
    echo "${devices[0]}"
    return
  fi

  if [[ "${#devices[@]}" -eq 0 ]]; then
    echo "No connected Android devices found." >&2
  else
    echo "Multiple Android devices detected. Please pass a device id." >&2
    adb devices >&2
  fi
  exit 1
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  local device_id flutter_cmd
  device_id="$(resolve_device_id "${1:-}")"
  flutter_cmd="$(resolve_flutter_cmd)"

  echo "Using Flutter command: $flutter_cmd"
  echo "Target Android device: $device_id"
  echo "Building latest debug APK..."
  (cd "$ROOT_DIR" && eval "$flutter_cmd build apk --debug")

  if [[ ! -f "$APK_PATH" ]]; then
    echo "Expected APK not found: $APK_PATH" >&2
    exit 1
  fi

  echo "Installing debug APK with adb overwrite install (-r -t)..."
  adb -s "$device_id" install -r -t "$APK_PATH"
}

main "$@"
