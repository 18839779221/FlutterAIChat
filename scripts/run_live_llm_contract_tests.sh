#!/usr/bin/env bash

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: bash scripts/run_live_llm_contract_tests.sh <provider-id> [provider-id ...]" >&2
  echo "Example: bash scripts/run_live_llm_contract_tests.sh beehears-responses minimax-anthropic" >&2
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

echo "Running live configurable_http_llm contract tests for: $provider_ids"
LIVE_LLM_PROVIDER_IDS="$provider_ids" \
  fvm flutter test --tags live-llm test/models/llm/configurable_http_llm_live_test.dart
