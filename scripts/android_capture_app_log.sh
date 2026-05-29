#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_PACKAGE="com.example.ai_chat"
APP_PACKAGE="${APP_PACKAGE:-$DEFAULT_PACKAGE}"
LOG_RELATIVE_PATH="files/logs/app.log"
OUTPUT_DIR="$ROOT_DIR/build/artifact-debug"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/android_capture_app_log.sh clear [device_id]
  bash scripts/android_capture_app_log.sh show [device_id]
  bash scripts/android_capture_app_log.sh export <name> [device_id]

Reads the app-private file log via adb run-as instead of logcat.

Commands:
  clear         Truncate the app-private files/logs/app.log before repro
  show          Print the current app-private files/logs/app.log to stdout
  export <name> Export the current app-private files/logs/app.log to
                build/artifact-debug/<name>.log

Arguments:
  device_id     Optional Android device serial. If omitted and exactly one
                connected device is available, that device is used.

Environment:
  APP_PACKAGE   Override the Android application id
                (default: com.example.ai_chat)
EOF
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

run_in_app() {
  local device_id="$1"
  local command="$2"
  adb -s "$device_id" shell run-as "$APP_PACKAGE" sh -c "$command"
}

clear_log() {
  local device_id="$1"
  run_in_app "$device_id" "mkdir -p files/logs && : > '$LOG_RELATIVE_PATH'"
  echo "Cleared $LOG_RELATIVE_PATH for package $APP_PACKAGE on device $device_id"
}

show_log() {
  local device_id="$1"
  run_in_app "$device_id" "test -f $LOG_RELATIVE_PATH && cat $LOG_RELATIVE_PATH"
}

export_log() {
  local name="$1"
  local device_id="$2"
  mkdir -p "$OUTPUT_DIR"
  local output_path="$OUTPUT_DIR/$name.log"
  run_in_app "$device_id" "test -f $LOG_RELATIVE_PATH && cat $LOG_RELATIVE_PATH" \
    > "$output_path"
  echo "Exported app log to $output_path"
}

main() {
  local command="${1:-}"
  if [[ -z "$command" || "$command" == "--help" || "$command" == "-h" ]]; then
    usage
    exit 0
  fi

  case "$command" in
    clear)
      local device_id
      device_id="$(resolve_device_id "${2:-}")"
      clear_log "$device_id"
      ;;
    show)
      local device_id
      device_id="$(resolve_device_id "${2:-}")"
      show_log "$device_id"
      ;;
    export)
      local name="${2:-}"
      if [[ -z "$name" ]]; then
        echo "Missing export name." >&2
        usage >&2
        exit 1
      fi
      local device_id
      device_id="$(resolve_device_id "${3:-}")"
      export_log "$name" "$device_id"
      ;;
    *)
      echo "Unknown command: $command" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
