#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LEAD_MODEL="${OC_LEAD_MODEL:-codex-for-me/gpt-5.2}"
DEV_MODEL="${OC_DEV_MODEL:-codex-for-me/gpt-5.3-codex}"
QA_MODEL="${OC_QA_MODEL:-codex-for-me/gpt-5.2}"
CONTEXT_TOKENS="${OC_CONTEXT_TOKENS:-160000}"
APPLY_CONFIG=1
FULL_TEAM=0
BIND_FEISHU_LEAD=1

usage() {
  cat <<'EOF'
Usage:
  scripts/oc-team-setup.sh [options]

Options:
  --no-config  Do not modify agents.defaults config
  --full-team  Also ensure pm/architect/release agents
  --no-feishu-bind  Skip binding Feishu route to lead
  -h, --help   Show this help
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

agent_exists() {
  local agent="$1"
  openclaw agents list --json 2>/dev/null | rg -q "\"id\"\\s*:\\s*\"${agent}\""
}

ensure_agent() {
  local agent="$1"
  local workspace="$2"
  local model="$3"

  mkdir -p "${workspace}"
  if agent_exists "${agent}"; then
    echo "[skip] agent '${agent}' already exists"
    return 0
  fi

  echo "[add] agent '${agent}'"
  openclaw agents add "${agent}" \
    --workspace "${workspace}" \
    --model "${model}" \
    --non-interactive
}

add_allowlist_if_exists() {
  local agent="$1"
  local tool_name="$2"

  local bin_path
  bin_path="$(command -v "${tool_name}" || true)"
  if [[ -z "${bin_path}" ]]; then
    echo "[warn] '${tool_name}' not found in PATH; skip allowlist for agent '${agent}'"
    return 0
  fi

  openclaw approvals allowlist add --agent "${agent}" "${bin_path}" >/dev/null 2>&1 || true
  echo "[ok] allowlist ${agent} -> ${bin_path}"
}

sync_lead_skill() {
  local skill_name="lead-feishu-flow"
  local src="${REPO_ROOT}/skills/${skill_name}"
  local lead_dst="${REPO_ROOT}/.openclaw/lead/skills/${skill_name}"
  local managed_dst="${HOME}/.openclaw/skills/${skill_name}"

  if [[ ! -f "${src}/SKILL.md" ]]; then
    echo "[warn] lead skill source missing: ${src}/SKILL.md"
    return 0
  fi

  mkdir -p "${lead_dst}" "${managed_dst}"
  cp -R "${src}/." "${lead_dst}/"
  cp -R "${src}/." "${managed_dst}/"
  echo "[ok] synced skill '${skill_name}' to lead workspace + managed skills"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-config)
        APPLY_CONFIG=0
        shift
        ;;
      --full-team)
        FULL_TEAM=1
        shift
        ;;
      --no-feishu-bind)
        BIND_FEISHU_LEAD=0
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

  require_cmd openclaw
  require_cmd rg

  if [[ "${APPLY_CONFIG}" -eq 1 ]]; then
    echo "[config] context + compaction defaults"
    openclaw config set agents.defaults.contextTokens "${CONTEXT_TOKENS}" >/dev/null
    openclaw config set agents.defaults.compaction.mode '"safeguard"' >/dev/null
  else
    echo "[skip] config update disabled (--no-config)"
  fi

  ensure_agent "lead" "${REPO_ROOT}/.openclaw/lead" "${LEAD_MODEL}"
  ensure_agent "flutter-dev" "${REPO_ROOT}/.openclaw/flutter-dev" "${DEV_MODEL}"
  ensure_agent "qa" "${REPO_ROOT}/.openclaw/qa" "${QA_MODEL}"
  sync_lead_skill

  if [[ "${FULL_TEAM}" -eq 1 ]]; then
    ensure_agent "pm" "${REPO_ROOT}/.openclaw/pm" "${LEAD_MODEL}"
    ensure_agent "architect" "${REPO_ROOT}/.openclaw/architect" "${LEAD_MODEL}"
    ensure_agent "release" "${REPO_ROOT}/.openclaw/release" "${LEAD_MODEL}"
  fi

  add_allowlist_if_exists "lead" "git"
  add_allowlist_if_exists "lead" "bash"
  add_allowlist_if_exists "lead" "openclaw"
  if [[ "${BIND_FEISHU_LEAD}" -eq 1 ]]; then
    openclaw agents bind --agent lead --bind feishu >/dev/null 2>&1 || true
    echo "[ok] route feishu -> lead"
  else
    echo "[skip] feishu binding disabled (--no-feishu-bind)"
  fi

  add_allowlist_if_exists "flutter-dev" "git"
  add_allowlist_if_exists "flutter-dev" "flutter"
  add_allowlist_if_exists "flutter-dev" "dart"

  add_allowlist_if_exists "qa" "git"
  add_allowlist_if_exists "qa" "flutter"
  add_allowlist_if_exists "qa" "dart"

  if [[ "${FULL_TEAM}" -eq 1 ]]; then
    add_allowlist_if_exists "release" "git"
  fi

  echo
  echo "Agent team setup complete."
  openclaw agents list --bindings
}

main "$@"
