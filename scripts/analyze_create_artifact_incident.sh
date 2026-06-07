#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_EXPORT_NAME="latest"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/analyze_create_artifact_incident.sh latest [device_id] [--flow-id <flowId>] [--trace-id <traceId>]
  bash scripts/analyze_create_artifact_incident.sh file <log_path> [--flow-id <flowId>] [--trace-id <traceId>]

Commands:
  latest        Export the current Android app log to build/artifact-debug/latest.log,
                then print both the artifact render report and streaming timeline report.
  file          Analyze an existing log file.
EOF
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
  local flow_id=""
  local trace_id=""

  case "$command" in
    latest)
      if [[ "${1:-}" != "" && "${1:0:1}" != "-" ]]; then
        device_id="$1"
        shift
      fi
      bash "$ROOT_DIR/scripts/android_capture_app_log.sh" export "$DEFAULT_EXPORT_NAME" "$device_id"
      log_path="$ROOT_DIR/build/artifact-debug/${DEFAULT_EXPORT_NAME}.log"
      ;;
    file)
      log_path="${1:-}"
      if [[ -z "$log_path" ]]; then
        echo "Missing log path." >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
    *)
      echo "Unknown command: $command" >&2
      usage >&2
      exit 1
      ;;
  esac

  while (($# > 0)); do
    case "$1" in
      --flow-id)
        flow_id="${2:-}"
        shift 2
        ;;
      --trace-id)
        trace_id="${2:-}"
        shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  echo "=== Artifact Render Report ==="
  local -a artifact_cmd=(
    bash
    "$ROOT_DIR/scripts/analyze_create_artifact_render.sh"
    file
    "$log_path"
    --report
  )
  if [[ -n "$flow_id" ]]; then
    artifact_cmd+=(--flow-id "$flow_id")
  fi
  "${artifact_cmd[@]}"
  echo
  echo "=== Streaming Timeline Report ==="
  local -a timeline_cmd=(
    bash
    "$ROOT_DIR/scripts/analyze_streaming_trace.sh"
    file
    "$log_path"
    --report
  )
  if [[ -n "$trace_id" ]]; then
    timeline_cmd+=(--trace-id "$trace_id")
  fi
  "${timeline_cmd[@]}"
}

main "$@"
