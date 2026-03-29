#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DEFAULTS_PATH="${ROOT_DIR}/config/local_defaults.json"
DROIDRUN_CONFIG_PATH="${ROOT_DIR}/config/droidrun.smoke.yaml"
DROIDRUN_VENV_PATH="${DROIDRUN_VENV_PATH:-/Users/skka/androidSpace/droidrun/.venv}"
DEFAULT_DEVICE_SERIAL="${ANDROID_SERIAL:-AUUNW22B08000071}"
APP_PACKAGE="${APP_PACKAGE:-com.example.ai_chat}"
APP_ACTIVITY="${APP_ACTIVITY:-.MainActivity}"
DEFAULT_SMOKE_MESSAGE="droidrun smoke $(date +%Y%m%d-%H%M%S)"
SMOKE_MESSAGE="${SMOKE_MESSAGE:-${DEFAULT_SMOKE_MESSAGE}}"
RUNTIME_CONFIG_DIR="${ROOT_DIR}/build/droidrun"
RUNTIME_CONFIG_PATH="${RUNTIME_CONFIG_DIR}/runtime-smoke.yaml"

if [[ ! -f "${LOCAL_DEFAULTS_PATH}" ]]; then
  echo "Missing ${LOCAL_DEFAULTS_PATH}" >&2
  exit 1
fi

if [[ ! -x "${DROIDRUN_VENV_PATH}/bin/droidrun" ]]; then
  echo "Missing droidrun executable at ${DROIDRUN_VENV_PATH}/bin/droidrun" >&2
  exit 1
fi

mkdir -p "${RUNTIME_CONFIG_DIR}"

python3 - <<'PY'
import json
from pathlib import Path

base_config = Path("config/droidrun.smoke.yaml").read_text().rstrip()
local_defaults = json.loads(Path("config/local_defaults.json").read_text())

provider_block = f"""
llm_profiles:
  manager:
    provider: OpenAILike
    model: {local_defaults["model"]}
    temperature: 0.1
    api_base: {local_defaults["base_url"]}
    kwargs:
      api_key: {local_defaults["api_key"]}
  executor:
    provider: OpenAILike
    model: {local_defaults["model"]}
    temperature: 0.0
    api_base: {local_defaults["base_url"]}
    kwargs:
      api_key: {local_defaults["api_key"]}
  fast_agent:
    provider: OpenAILike
    model: {local_defaults["model"]}
    temperature: 0.0
    api_base: {local_defaults["base_url"]}
    kwargs:
      api_key: {local_defaults["api_key"]}
  text_manipulator:
    provider: OpenAILike
    model: {local_defaults["model"]}
    temperature: 0.0
    api_base: {local_defaults["base_url"]}
    kwargs:
      api_key: {local_defaults["api_key"]}
  app_opener:
    provider: OpenAILike
    model: {local_defaults["model"]}
    temperature: 0.0
    api_base: {local_defaults["base_url"]}
    kwargs:
      api_key: {local_defaults["api_key"]}
  scripter:
    provider: OpenAILike
    model: {local_defaults["model"]}
    temperature: 0.0
    api_base: {local_defaults["base_url"]}
    kwargs:
      api_key: {local_defaults["api_key"]}
""".strip()

Path("build/droidrun/runtime-smoke.yaml").write_text(
    f"{base_config}\n\n{provider_block}\n"
)
PY

TASK_PROMPT=$(
  cat <<EOF
The Flutter app ai_chat is already open on screen.
Find the message input box near the bottom.
Type "${SMOKE_MESSAGE}" into the message input.
Tap the send button once.
Verify that the user message "${SMOKE_MESSAGE}" is visible in the conversation.
If the first tap does not send the message, tap the send button one more time.
Finish only after the user message is visible in the chat area.
EOF
)

echo "Preparing Android device ${DEFAULT_DEVICE_SERIAL}..."
adb -s "${DEFAULT_DEVICE_SERIAL}" wait-for-device
adb -s "${DEFAULT_DEVICE_SERIAL}" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb -s "${DEFAULT_DEVICE_SERIAL}" shell wm dismiss-keyguard >/dev/null 2>&1 || true
adb -s "${DEFAULT_DEVICE_SERIAL}" shell ime set com.droidrun.portal/.input.DroidrunKeyboardIME >/dev/null 2>&1 || true
adb -s "${DEFAULT_DEVICE_SERIAL}" shell monkey -p "${APP_PACKAGE}" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 2

CURRENT_TOP_ACTIVITY="$(
  adb -s "${DEFAULT_DEVICE_SERIAL}" shell dumpsys activity activities \
    | grep -m 1 -E 'mResumedActivity|topResumedActivity' \
    || true
)"

if [[ "${CURRENT_TOP_ACTIVITY}" != *"${APP_PACKAGE}"* ]]; then
  echo "App is not in foreground after prewarm. Unlock the device and retry." >&2
  echo "Detected top activity: ${CURRENT_TOP_ACTIVITY}" >&2
  exit 2
fi

echo "Running Droidrun smoke test on ${DEFAULT_DEVICE_SERIAL}..."
"${DROIDRUN_VENV_PATH}/bin/droidrun" run "${TASK_PROMPT}" \
  --config "${RUNTIME_CONFIG_PATH}" \
  --device "${DEFAULT_DEVICE_SERIAL}" \
  --vision \
  --no-reasoning \
  --no-tracing
