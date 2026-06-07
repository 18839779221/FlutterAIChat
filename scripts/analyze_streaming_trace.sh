#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_EXPORT_NAME="latest"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/analyze_streaming_trace.sh latest [device_id] [--trace-id <traceId>] [--json] [--report]
  bash scripts/analyze_streaming_trace.sh file <log_path> [--trace-id <traceId>] [--json] [--report]

Commands:
  latest        Export the current Android app log to build/artifact-debug/latest.log,
                then analyze the latest streaming timeline trace.
  file          Analyze an existing log file.
EOF
}

resolve_dart_cmd() {
  local flutter_version
  flutter_version="$(flutter --version 2>/dev/null | head -n 1 || true)"
  if [[ "$flutter_version" == *"3.35.7"* ]]; then
    printf '%s\n' "dart"
    return
  fi
  printf '%s\n' "fvm"
  printf '%s\n' "dart"
}

main() {
  local command="${1:-}"
  if [[ -z "$command" || "$command" == "--help" || "$command" == "-h" ]]; then
    usage
    exit 0
  fi

  shift
  local log_path=""
  local device_id=""
  local -a analyzer_args=()

  case "$command" in
    latest)
      if [[ "${1:-}" != "" && "${1:0:1}" != "-" ]]; then
        device_id="$1"
        shift
      fi
      bash "$ROOT_DIR/scripts/android_capture_app_log.sh" export "$DEFAULT_EXPORT_NAME" "$device_id"
      log_path="$ROOT_DIR/build/artifact-debug/${DEFAULT_EXPORT_NAME}.log"
      analyzer_args=("$@")
      ;;
    file)
      log_path="${1:-}"
      if [[ -z "$log_path" ]]; then
        echo "Missing log path." >&2
        usage >&2
        exit 1
      fi
      shift
      analyzer_args=("$@")
      ;;
    *)
      echo "Unknown command: $command" >&2
      usage >&2
      exit 1
      ;;
  esac

  local -a dart_cmd=()
  while IFS= read -r part; do
    if [[ -n "$part" ]]; then
      dart_cmd+=("$part")
    fi
  done < <(resolve_dart_cmd)
  cd "$ROOT_DIR"
  local -a cmd=(
    "${dart_cmd[@]}"
    run
    tool/analyze_streaming_trace_log.dart
    "$log_path"
  )
  if ((${#analyzer_args[@]} > 0)); then
    cmd+=("${analyzer_args[@]}")
  fi
  "${cmd[@]}"
}

main "$@"
