#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_FLUTTER_VERSION="3.35.7"
APP_PATH="$ROOT_DIR/build/ios/iphoneos/Runner.app"

usage() {
  cat <<'EOF'
Usage: bash scripts/ios_install_release.sh [device_id] [--no-launch] [--skip-build]

Builds the latest signed iOS release app, installs it to a connected iPhone or
iPad with devicectl, verifies the install, and launches it when possible.

Arguments:
  device_id      Optional CoreDevice identifier. If omitted and exactly one
                 available paired iOS device is connected, that device is used.

Options:
  --no-launch    Skip the post-install launch attempt.
  --skip-build   Reuse an existing build/ios/iphoneos/Runner.app artifact.
  -h, --help     Show this help message.
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

  if [[ -n "${IOS_DEVICE_ID:-}" ]]; then
    echo "$IOS_DEVICE_ID"
    return
  fi

  local devices=()
  while IFS= read -r device; do
    if [[ -n "$device" ]]; then
      devices+=("$device")
    fi
  done < <(xcrun devicectl list devices \
    --filter "State CONTAINS 'available'" \
    --hide-default-columns \
    --columns Identifier \
    --hide-headers)

  if [[ "${#devices[@]}" -eq 1 ]]; then
    echo "${devices[0]}"
    return
  fi

  if [[ "${#devices[@]}" -eq 0 ]]; then
    echo "No available paired iOS devices found." >&2
  else
    echo "Multiple available paired iOS devices detected. Please pass a device id." >&2
    xcrun devicectl list devices >&2
  fi
  exit 1
}

build_release_app() {
  local flutter_cmd="$1"
  echo "Using Flutter command: $flutter_cmd"
  echo "Building latest signed iOS release app..."
  (cd "$ROOT_DIR" && eval "$flutter_cmd build ios --release")
}

read_bundle_id() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist"
}

verify_app_exists() {
  if [[ ! -d "$APP_PATH" ]]; then
    echo "Expected app bundle not found: $APP_PATH" >&2
    exit 1
  fi
}

install_app() {
  local device_id="$1"
  echo "Installing release app to iOS device: $device_id"
  xcrun devicectl device install app --device "$device_id" "$APP_PATH"
}

verify_installed() {
  local device_id="$1"
  local bundle_id="$2"
  echo "Verifying installed app bundle: $bundle_id"
  xcrun devicectl device info apps --device "$device_id" --bundle-id "$bundle_id"
}

launch_app() {
  local device_id="$1"
  local bundle_id="$2"
  local output

  set +e
  output="$(xcrun devicectl device process launch \
    --device "$device_id" \
    --terminate-existing \
    "$bundle_id" 2>&1)"
  local status=$?
  set -e

  echo "$output"

  if [[ $status -eq 0 ]]; then
    return 0
  fi

  # A locked device rejects remote launch even after a successful install.
  if [[ "$output" == *"could not be, unlocked"* || "$output" == *"BSErrorCodeDescription = Locked"* ]]; then
    echo "App is installed, but the device is locked. Unlock it and open the app manually."
    return 0
  fi

  return $status
}

main() {
  local requested_device=""
  local should_launch=1
  local should_build=1

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --no-launch)
        should_launch=0
        ;;
      --skip-build)
        should_build=0
        ;;
      -*)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
      *)
        if [[ -n "$requested_device" ]]; then
          echo "Only one device id may be provided." >&2
          usage >&2
          exit 1
        fi
        requested_device="$1"
        ;;
    esac
    shift
  done

  local device_id flutter_cmd bundle_id
  device_id="$(resolve_device_id "$requested_device")"
  flutter_cmd="$(resolve_flutter_cmd)"

  if [[ $should_build -eq 1 ]]; then
    build_release_app "$flutter_cmd"
  fi

  verify_app_exists
  bundle_id="$(read_bundle_id)"

  install_app "$device_id"
  verify_installed "$device_id" "$bundle_id"

  if [[ $should_launch -eq 1 ]]; then
    echo "Launching installed app..."
    launch_app "$device_id" "$bundle_id"
  fi

  echo "iOS release install flow completed at: $(date '+%Y-%m-%d %H:%M:%S')"
}

main "$@"
