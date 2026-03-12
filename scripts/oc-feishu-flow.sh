#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FEATURE_ID=""
REQ_TEXT=""
REQ_FILE=""
WITH_ARCHITECT=0
AUTO_COMMIT=1
REQUIRE_GATEWAY=1
MAX_ATTEMPTS=3
SESSION_TAG=""
STATUS_MODE=0
DRY_RUN=0

usage() {
  cat <<'EOF_USAGE'
Usage:
  scripts/oc-feishu-flow.sh --req "<requirement>" [options]
  scripts/oc-feishu-flow.sh --req-file <path> [--id <feature-id>] [options]
  scripts/oc-feishu-flow.sh --status --id <feature-id>

Options:
  --id <feature-id>        Feature id. Default: feat-YYYYmmdd-HHMMSS
  --req <text>             Requirement text
  --req-file <path>        Requirement file
  --with-architect         Enable architect stage
  --auto-commit            Auto commit at release stage (default)
  --no-auto-commit         Disable auto commit
  --require-gateway        Require gateway health check (default)
  --no-require-gateway     Skip strict gateway health check
  --max-attempts <n>       Retry attempts for each stage (default: 3)
  --session-tag <tag>      Optional session tag
  --status                 Print local status for an existing feature id
  --dry-run                Print the command only
  -h, --help               Show this help
EOF_USAGE
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

generate_feature_id() {
  date '+feat-%Y%m%d-%H%M%S'
}

print_status() {
  local branch="feature/${FEATURE_ID}"
  local artifact_dir="${REPO_ROOT}/docs/ai/${FEATURE_ID}"

  echo "[status] feature=${FEATURE_ID}"
  echo "[status] repo=${REPO_ROOT}"

  if git -C "${REPO_ROOT}" show-ref --verify --quiet "refs/heads/${branch}"; then
    echo "[status] branch=${branch} (exists)"
    git -C "${REPO_ROOT}" log -1 --pretty='[status] last-commit=%h %s (%ci)' "${branch}"
  else
    echo "[status] branch=${branch} (missing)"
  fi

  if [[ -d "${artifact_dir}" ]]; then
    echo "[status] artifacts=${artifact_dir}"
    ls -1 "${artifact_dir}" | sed 's/^/[status] file=/'
  else
    echo "[status] artifacts missing: ${artifact_dir}"
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)
        FEATURE_ID="$2"
        shift 2
        ;;
      --req)
        REQ_TEXT="$2"
        shift 2
        ;;
      --req-file)
        REQ_FILE="$2"
        shift 2
        ;;
      --with-architect)
        WITH_ARCHITECT=1
        shift
        ;;
      --auto-commit)
        AUTO_COMMIT=1
        shift
        ;;
      --no-auto-commit)
        AUTO_COMMIT=0
        shift
        ;;
      --require-gateway)
        REQUIRE_GATEWAY=1
        shift
        ;;
      --no-require-gateway)
        REQUIRE_GATEWAY=0
        shift
        ;;
      --max-attempts)
        MAX_ATTEMPTS="$2"
        shift 2
        ;;
      --session-tag)
        SESSION_TAG="$2"
        shift 2
        ;;
      --status)
        STATUS_MODE=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  require_cmd bash
  require_cmd git

  if [[ -z "${FEATURE_ID}" ]]; then
    FEATURE_ID="$(generate_feature_id)"
  fi

  if [[ "${STATUS_MODE}" -eq 1 ]]; then
    print_status
    exit 0
  fi

  if [[ -z "${REQ_TEXT}" && -z "${REQ_FILE}" ]]; then
    echo "Either --req or --req-file is required." >&2
    usage
    exit 1
  fi

  if [[ -n "${REQ_TEXT}" && -n "${REQ_FILE}" ]]; then
    echo "Use either --req or --req-file, not both." >&2
    exit 1
  fi

  if [[ ! -x "${REPO_ROOT}/scripts/oc-feature.sh" ]]; then
    echo "Missing executable: ${REPO_ROOT}/scripts/oc-feature.sh" >&2
    exit 1
  fi

  local cmd=(bash "${REPO_ROOT}/scripts/oc-feature.sh" "${FEATURE_ID}" --max-attempts "${MAX_ATTEMPTS}")
  if [[ -n "${REQ_TEXT}" ]]; then
    cmd+=(--req "${REQ_TEXT}")
  else
    cmd+=(--req-file "${REQ_FILE}")
  fi

  if [[ "${WITH_ARCHITECT}" -eq 1 ]]; then
    cmd+=(--with-architect)
  fi
  if [[ "${AUTO_COMMIT}" -eq 1 ]]; then
    cmd+=(--auto-commit)
  fi
  if [[ "${REQUIRE_GATEWAY}" -eq 1 ]]; then
    cmd+=(--require-gateway)
  fi
  if [[ -n "${SESSION_TAG}" ]]; then
    cmd+=(--session-tag "${SESSION_TAG}")
  fi

  echo "[flow] feature=${FEATURE_ID}"
  echo "[flow] repo=${REPO_ROOT}"
  printf '[flow] cmd='
  printf '%q ' "${cmd[@]}"
  echo

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    exit 0
  fi

  "${cmd[@]}"

  echo "[done] feature=${FEATURE_ID}"
  echo "[done] branch=$(git -C "${REPO_ROOT}" branch --show-current)"
  git -C "${REPO_ROOT}" log -1 --pretty='[done] head=%h %s (%ci)'
  echo "[done] artifacts=${REPO_ROOT}/docs/ai/${FEATURE_ID}"
}

main "$@"
