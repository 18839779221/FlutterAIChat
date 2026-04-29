#!/usr/bin/env bash

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: bash scripts/run_live_llm_contract_tests.sh <provider-id> [provider-id ...]" >&2
  echo "Example: bash scripts/run_live_llm_contract_tests.sh minimax-openai minimax-anthropic" >&2
  echo "Tip: set LIVE_LLM_LOCAL_DEFAULTS_PATH when this worktree does not contain config/local_defaults.json" >&2
  exit 1
fi

provider_ids=""
for provider_id in "$@"; do
  if [[ -n "$provider_ids" ]]; then
    provider_ids+=","
  fi
  provider_ids+="$provider_id"
done

echo "Running local configurable_http_llm contract tests..."
fvm flutter test test/models/llm/configurable_http_llm_test.dart

echo "Provider preference reminder: prefer minimax/deepseek base URLs when available."
if [[ -n "${LIVE_LLM_LOCAL_DEFAULTS_PATH:-}" ]]; then
  echo "Using injected local defaults path: $LIVE_LLM_LOCAL_DEFAULTS_PATH"
fi

echo "Running live configurable_http_llm contract tests for: $provider_ids"
LIVE_LLM_PROVIDER_IDS="$provider_ids" \
  fvm flutter test --tags live-llm test/models/llm/configurable_http_llm_live_test.dart
