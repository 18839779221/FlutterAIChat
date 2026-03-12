#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

AUTO_COMMIT=0
WITH_ARCHITECT=0
SESSION_TAG=""
REQUIRE_GATEWAY=0
ISOLATE_AGENTS=1
KEEP_RUN_AGENTS=0
MAX_ATTEMPTS=3
REQUIRE_FLUTTER=0

REQUIREMENT_TEXT=""
REQ_FILE=""

RUN_AGENTS=()
AGENTS_JSON=""
BASE_HEAD=""

usage() {
  cat <<'EOF_USAGE'
Usage:
  scripts/oc-feature.sh <feature-id> --req "<requirement>"
  scripts/oc-feature.sh <feature-id> --req-file <path>

Options:
  --with-architect       Add architect stage to refine 02-design.md
  --session-tag <tag>    Session suffix; default is timestamp per run
  --auto-commit          Auto commit after release stage generates commit message file
  --no-isolate-agents    Reuse base agents instead of run-scoped agents
  --keep-run-agents      Keep run-scoped agents after script exits
  --require-gateway      Fail preflight if gateway health check fails
  --require-flutter      Fail preflight if flutter command is missing
  --max-attempts <n>     Per-stage retry attempts (default: 3)
  -h, --help             Show this help
EOF_USAGE
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

sanitize_tag() {
  printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '-'
}

agent_exists() {
  local id="$1"
  echo "${AGENTS_JSON}" | jq -e --arg id "${id}" '.[] | select(.id == $id)' >/dev/null 2>&1
}

agent_field() {
  local id="$1"
  local field="$2"
  echo "${AGENTS_JSON}" | jq -r --arg id "${id}" --arg field "${field}" '.[] | select(.id == $id) | .[$field] // empty' | head -n1
}

copy_bootstrap_files() {
  local src_workspace="$1"
  local dst_workspace="$2"
  local files=(AGENTS.md SOUL.md TOOLS.md IDENTITY.md USER.md HEARTBEAT.md BOOTSTRAP.md)

  mkdir -p "${dst_workspace}"
  for f in "${files[@]}"; do
    if [[ -f "${src_workspace}/${f}" ]]; then
      cp -f "${src_workspace}/${f}" "${dst_workspace}/${f}"
    fi
  done
}

add_allowlist_if_exists() {
  local agent="$1"
  local bin_name="$2"

  local bin_path
  bin_path="$(command -v "${bin_name}" || true)"
  if [[ -n "${bin_path}" ]]; then
    openclaw approvals allowlist add --agent "${agent}" "${bin_path}" >/dev/null 2>&1 || true
  fi
}

setup_run_agent() {
  local base_agent="$1"
  local session_tag_safe="$2"

  if [[ "${ISOLATE_AGENTS}" -eq 0 ]]; then
    echo "${base_agent}"
    return 0
  fi

  local run_agent="${base_agent}-run-${session_tag_safe}"
  run_agent="$(sanitize_tag "${run_agent}")"

  if agent_exists "${run_agent}"; then
    echo "${run_agent}"
    return 0
  fi

  local model workspace run_workspace
  model="$(agent_field "${base_agent}" "model")"
  workspace="$(agent_field "${base_agent}" "workspace")"

  if [[ -z "${model}" || -z "${workspace}" ]]; then
    echo "Base agent not found or missing model/workspace: ${base_agent}" >&2
    exit 1
  fi

  run_workspace="${REPO_ROOT}/.openclaw/runs/${session_tag_safe}/${base_agent}"
  copy_bootstrap_files "${workspace}" "${run_workspace}"

  echo "[setup] creating run agent ${run_agent}" >&2
  openclaw agents add "${run_agent}" \
    --workspace "${run_workspace}" \
    --model "${model}" \
    --non-interactive >/dev/null

  add_allowlist_if_exists "${run_agent}" "git"
  if [[ "${base_agent}" == "flutter-dev" || "${base_agent}" == "qa" ]]; then
    add_allowlist_if_exists "${run_agent}" "flutter"
    add_allowlist_if_exists "${run_agent}" "dart"
  fi

  RUN_AGENTS+=("${run_agent}")

  AGENTS_JSON="$(openclaw agents list --json)"
  echo "${run_agent}"
}

cleanup_run_agents() {
  if [[ "${ISOLATE_AGENTS}" -eq 0 || "${KEEP_RUN_AGENTS}" -eq 1 ]]; then
    return 0
  fi

  local agent
  for agent in "${RUN_AGENTS[@]:-}"; do
    if [[ -n "${agent}" ]]; then
      openclaw agents delete "${agent}" --force >/dev/null 2>&1 || true
    fi
  done
}

check_stage_output() {
  local out_file="$1"

  if ! jq -e '.status == "ok"' "${out_file}" >/dev/null 2>&1; then
    return 1
  fi

  local stop_reason
  stop_reason="$(jq -r '.result.stopReason // "stop"' "${out_file}" 2>/dev/null || echo "error")"
  if [[ "${stop_reason}" == "error" ]]; then
    return 1
  fi

  local text_blob
  text_blob="$(jq -r '[.result.payloads[]?.text // ""] | join("\n")' "${out_file}" 2>/dev/null || true)"

  if printf '%s' "${text_blob}" | rg -qi 'Invalid prompt|All models failed|timed out|gateway agent failed'; then
    return 1
  fi

  return 0
}

assert_head_unchanged() {
  local stage="$1"
  local current_head
  current_head="$(git rev-parse HEAD)"
  if [[ "${current_head}" != "${BASE_HEAD}" ]]; then
    echo "[error] stage '${stage}' created an unexpected commit (${current_head}). aborting for safety." >&2
    exit 1
  fi
}

run_agent() {
  local stage="$1"
  local agent="$2"
  local session="$3"
  local prompt="$4"
  local out_file="$5"

  local attempt=1
  local tmp_file="${out_file}.tmp"

  while (( attempt <= MAX_ATTEMPTS )); do
    echo
    echo "==> [${stage}] agent=${agent} attempt=${attempt}/${MAX_ATTEMPTS}"

    if openclaw agent \
      --agent "${agent}" \
      --session-id "${session}" \
      --message "${prompt}" \
      --timeout 1200 \
      --json >"${tmp_file}"; then
      mv "${tmp_file}" "${out_file}"
    else
      if [[ -f "${tmp_file}" ]]; then
        mv "${tmp_file}" "${out_file}"
      fi
    fi

    if [[ -f "${out_file}" ]]; then
      cat "${out_file}"
    fi

    if [[ -f "${out_file}" ]] && check_stage_output "${out_file}"; then
      assert_head_unchanged "${stage}"
      return 0
    fi

    if (( attempt < MAX_ATTEMPTS )); then
      sleep 3
    fi

    attempt=$((attempt + 1))
  done

  echo "[error] stage '${stage}' failed after ${MAX_ATTEMPTS} attempts" >&2
  return 1
}

preflight() {
  require_cmd openclaw
  require_cmd git
  require_cmd jq
  require_cmd rg

  if [[ "${REQUIRE_GATEWAY}" -eq 1 ]]; then
    if ! openclaw gateway health >/dev/null 2>&1; then
      echo "[error] gateway health check failed (--require-gateway)." >&2
      exit 1
    fi
  fi

  if [[ "${REQUIRE_FLUTTER}" -eq 1 ]]; then
    if ! command -v flutter >/dev/null 2>&1; then
      echo "[error] flutter command not found (--require-flutter)." >&2
      exit 1
    fi
  fi
}

stage_ai_artifacts() {
  local ai_dir="$1"
  local files=(
    "${ai_dir}/00-input.md"
    "${ai_dir}/01-requirement.md"
    "${ai_dir}/02-design.md"
    "${ai_dir}/03-dev-notes.md"
    "${ai_dir}/04-test-report.md"
    "${ai_dir}/05-release.md"
    "${ai_dir}/06-commit-message.txt"
  )

  local f
  for f in "${files[@]}"; do
    if [[ -f "${f}" ]]; then
      git add "${f}"
    fi
  done
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

FEATURE_ID="$1"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --req)
      REQUIREMENT_TEXT="${2:-}"
      shift 2
      ;;
    --req-file)
      REQ_FILE="${2:-}"
      shift 2
      ;;
    --auto-commit)
      AUTO_COMMIT=1
      shift
      ;;
    --with-architect)
      WITH_ARCHITECT=1
      shift
      ;;
    --session-tag)
      SESSION_TAG="${2:-}"
      shift 2
      ;;
    --no-isolate-agents)
      ISOLATE_AGENTS=0
      shift
      ;;
    --keep-run-agents)
      KEEP_RUN_AGENTS=1
      shift
      ;;
    --require-gateway)
      REQUIRE_GATEWAY=1
      shift
      ;;
    --require-flutter)
      REQUIRE_FLUTTER=1
      shift
      ;;
    --max-attempts)
      MAX_ATTEMPTS="${2:-3}"
      shift 2
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

if [[ -z "${REQUIREMENT_TEXT}" && -z "${REQ_FILE}" ]]; then
  echo "Provide either --req or --req-file" >&2
  exit 1
fi

if [[ -n "${REQUIREMENT_TEXT}" && -n "${REQ_FILE}" ]]; then
  echo "Use only one of --req or --req-file" >&2
  exit 1
fi

if [[ -n "${REQ_FILE}" ]]; then
  if [[ ! -f "${REQ_FILE}" ]]; then
    echo "Requirement file not found: ${REQ_FILE}" >&2
    exit 1
  fi
  REQUIREMENT_TEXT="$(cat "${REQ_FILE}")"
fi

if [[ -z "${SESSION_TAG}" ]]; then
  SESSION_TAG="$(date '+%Y%m%d-%H%M%S')"
fi

SESSION_TAG_SAFE="$(sanitize_tag "${SESSION_TAG}")"

preflight

cd "${REPO_ROOT}"

BRANCH="feature/${FEATURE_ID}"
if git rev-parse --verify "${BRANCH}" >/dev/null 2>&1; then
  git checkout "${BRANCH}" >/dev/null
else
  git checkout -b "${BRANCH}" >/dev/null
fi

BASE_HEAD="$(git rev-parse HEAD)"
AGENTS_JSON="$(openclaw agents list --json)"

trap cleanup_run_agents EXIT

LEAD_AGENT="$(setup_run_agent "lead" "${SESSION_TAG_SAFE}")"
DEV_AGENT="$(setup_run_agent "flutter-dev" "${SESSION_TAG_SAFE}")"
QA_AGENT="$(setup_run_agent "qa" "${SESSION_TAG_SAFE}")"
ARCH_AGENT=""
if [[ "${WITH_ARCHITECT}" -eq 1 ]]; then
  ARCH_AGENT="$(setup_run_agent "architect" "${SESSION_TAG_SAFE}")"
fi

if [[ "${ISOLATE_AGENTS}" -eq 1 ]]; then
  echo "[setup] restarting gateway to load run-scoped agent config"
  openclaw gateway restart >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if openclaw gateway health >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

AI_DIR="${REPO_ROOT}/docs/ai/${FEATURE_ID}"
mkdir -p "${AI_DIR}/logs"

REQ_INPUT_FILE="${AI_DIR}/00-input.md"
cat > "${REQ_INPUT_FILE}" <<EOF_REQ
# Feature Input

Feature ID: ${FEATURE_ID}
Session Tag: ${SESSION_TAG}
Lead Agent: ${LEAD_AGENT}
Dev Agent: ${DEV_AGENT}
QA Agent: ${QA_AGENT}

## Requirement
${REQUIREMENT_TEXT}
EOF_REQ

LEAD_PROMPT="$(cat <<EOF_LEAD
You are the lead engineer for this Flutter repository at ${REPO_ROOT}.
Read ${REQ_INPUT_FILE}.
Create:
1) ${AI_DIR}/01-requirement.md with acceptance criteria and implementation tasks.
2) ${AI_DIR}/02-design.md with a concise technical design (impacted files, data flow, risks, test strategy).
Keep design lightweight for a small project.
Do not run git commit.
EOF_LEAD
)"

ARCH_PROMPT="$(cat <<EOF_ARCH
You are the architect for this Flutter repository at ${REPO_ROOT}.
Read ${AI_DIR}/01-requirement.md and the current ${AI_DIR}/02-design.md draft.
Refine and finalize ${AI_DIR}/02-design.md.
Do not run git commit.
EOF_ARCH
)"

DEV_PROMPT="$(cat <<EOF_DEV
You are flutter-dev for this repository at ${REPO_ROOT}.
Read ${AI_DIR}/01-requirement.md and ${AI_DIR}/02-design.md.
Implement the feature end-to-end in code.
After implementation, write a short change summary with file list to ${AI_DIR}/03-dev-notes.md.
Do not run git commit.
EOF_DEV
)"

QA_PROMPT="$(cat <<EOF_QA
You are QA for this Flutter repository at ${REPO_ROOT}.
Validate the feature using:
1) flutter analyze
2) flutter test
3) if integration_test exists: flutter test integration_test
If any test fails, fix issues and rerun.
Write final results, failed/passed commands, and residual risks to ${AI_DIR}/04-test-report.md.
Do not run git commit.
EOF_QA
)"

LEAD_RELEASE_PROMPT="$(cat <<EOF_REL
You are lead engineer for this repo at ${REPO_ROOT}.
Inspect current git changes and docs under ${AI_DIR}.
Write PR description to ${AI_DIR}/05-release.md.
Write commit message file to ${AI_DIR}/06-commit-message.txt:
- line 1: Conventional Commit subject (<=72 chars)
- line 2: blank
- line 3+: body with bullets
Do not run git commit.
EOF_REL
)"

run_agent "lead-plan" "${LEAD_AGENT}" "${FEATURE_ID}-lead-${SESSION_TAG_SAFE}" "${LEAD_PROMPT}" "${AI_DIR}/logs/lead-plan.json"

if [[ "${WITH_ARCHITECT}" -eq 1 ]]; then
  run_agent "architect" "${ARCH_AGENT}" "${FEATURE_ID}-architect-${SESSION_TAG_SAFE}" "${ARCH_PROMPT}" "${AI_DIR}/logs/architect.json"
fi

run_agent "flutter-dev" "${DEV_AGENT}" "${FEATURE_ID}-dev-${SESSION_TAG_SAFE}" "${DEV_PROMPT}" "${AI_DIR}/logs/dev.json"
run_agent "qa" "${QA_AGENT}" "${FEATURE_ID}-qa-${SESSION_TAG_SAFE}" "${QA_PROMPT}" "${AI_DIR}/logs/qa.json"
run_agent "lead-release" "${LEAD_AGENT}" "${FEATURE_ID}-lead-release-${SESSION_TAG_SAFE}" "${LEAD_RELEASE_PROMPT}" "${AI_DIR}/logs/lead-release.json"

if [[ "${AUTO_COMMIT}" -eq 1 ]]; then
  COMMIT_FILE="${AI_DIR}/06-commit-message.txt"
  if [[ ! -s "${COMMIT_FILE}" ]]; then
    echo "Commit message file missing or empty: ${COMMIT_FILE}" >&2
    exit 1
  fi

  git add -u
  stage_ai_artifacts "${AI_DIR}"

  if git diff --cached --quiet; then
    echo "[warn] no staged changes; skip commit"
  else
    git commit -F "${COMMIT_FILE}"
    echo "[ok] commit created on ${BRANCH}"
  fi
fi

echo
echo "Pipeline complete."
echo "Artifacts: ${AI_DIR}"
echo "Branch: ${BRANCH}"
echo "Session Tag: ${SESSION_TAG}"
echo "Lead Agent: ${LEAD_AGENT}"
echo "Dev Agent: ${DEV_AGENT}"
echo "QA Agent: ${QA_AGENT}"
git status --short
