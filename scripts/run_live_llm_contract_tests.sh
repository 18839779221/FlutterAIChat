#!/usr/bin/env bash

set -euo pipefail

resolve_flutter_cmd() {
  if command -v fvm >/dev/null 2>&1; then
    echo "fvm flutter"
    return
  fi
  if command -v flutter >/dev/null 2>&1; then
    echo "flutter"
    return
  fi
  echo "Neither 'fvm' nor 'flutter' is available in PATH." >&2
  exit 1
}

infer_provider_style() {
  local provider_id="$1"
  case "$provider_id" in
    *anthropic*)
      echo "anthropic"
      ;;
    *responses*)
      echo "responses"
      ;;
    *openai*|*chat-completions*|*chat_completions*)
      echo "chat_completions"
      ;;
    *)
      echo ""
      ;;
  esac
}

run_live_test_for_provider() {
  local flutter_cmd="$1"
  local provider_id="$2"
  local style="$3"

  case "$style" in
    anthropic)
      echo "Running anthropic headless live tests for provider: $provider_id"
      echo "Note: some anthropic-compatible providers only reliably cover continuation/tool round-trip paths and may not always emit structured ask-user tool calls."
      HEADLESS_LIVE_PROVIDER_ANTHROPIC="$provider_id" \
        eval "$flutter_cmd test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_anthropic_test.dart"
      ;;
    responses)
      echo "Running responses headless live tests for provider: $provider_id"
      HEADLESS_LIVE_PROVIDER_RESPONSES="$provider_id" \
        eval "$flutter_cmd test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_responses_test.dart"
      ;;
    chat_completions)
      echo "Running chat completions headless live tests for provider: $provider_id"
      HEADLESS_LIVE_PROVIDER_CHAT_COMPLETIONS="$provider_id" \
        eval "$flutter_cmd test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_chat_completions_test.dart"
      ;;
    *)
      echo "Unable to infer API style for provider id '$provider_id'." >&2
      echo "Expected the id to contain one of: anthropic, responses, openai, chat-completions." >&2
      exit 1
      ;;
  esac
}

if [[ $# -eq 0 ]]; then
  echo "Usage: bash scripts/run_live_llm_contract_tests.sh <provider-id> [provider-id ...]" >&2
  echo "Example: bash scripts/run_live_llm_contract_tests.sh minimax-openai-chat-completions minimax-anthropic" >&2
  echo "Tip: set LIVE_LLM_LOCAL_DEFAULTS_PATH when this worktree does not contain config/local_defaults.json" >&2
  exit 1
fi

flutter_cmd="$(resolve_flutter_cmd)"

echo "Running local configurable_http_llm contract tests..."
eval "$flutter_cmd test test/models/llm/configurable_http_llm_test.dart"

echo "Provider preference reminder: prefer minimax/deepseek base URLs when available."
if [[ -n "${LIVE_LLM_LOCAL_DEFAULTS_PATH:-}" ]]; then
  echo "Using injected local defaults path: $LIVE_LLM_LOCAL_DEFAULTS_PATH"
fi

for provider_id in "$@"; do
  style="$(infer_provider_style "$provider_id")"
  run_live_test_for_provider "$flutter_cmd" "$provider_id" "$style"
done
