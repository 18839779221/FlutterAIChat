#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DROIDRUN_VENV_PATH="${DROIDRUN_VENV_PATH:-/Users/skka/androidSpace/droidrun/.venv}"
DEFAULT_DEVICE_SERIAL="${ANDROID_SERIAL:-AUUNW22B08000071}"
APP_PACKAGE="${APP_PACKAGE:-com.example.ai_chat}"
APP_ACTIVITY="${APP_ACTIVITY:-.MainActivity}"
DEFAULT_SMOKE_MESSAGE="droidrun smoke $(date +%Y%m%d-%H%M%S)"
SMOKE_MESSAGE="${SMOKE_MESSAGE:-${DEFAULT_SMOKE_MESSAGE}}"
EXPECTED_CONFIRMATION_TEXT="${EXPECTED_CONFIRMATION_TEXT:-}"

if [[ ! -x "${DROIDRUN_VENV_PATH}/bin/python" ]]; then
  echo "Missing python executable at ${DROIDRUN_VENV_PATH}/bin/python" >&2
  exit 1
fi

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

echo "Running Android driver smoke test on ${DEFAULT_DEVICE_SERIAL}..."
ANDROID_SERIAL="${DEFAULT_DEVICE_SERIAL}" \
APP_PACKAGE="${APP_PACKAGE}" \
APP_ACTIVITY="${APP_ACTIVITY}" \
SMOKE_MESSAGE="${SMOKE_MESSAGE}" \
EXPECTED_CONFIRMATION_TEXT="${EXPECTED_CONFIRMATION_TEXT}" \
"${DROIDRUN_VENV_PATH}/bin/python" scripts/android_droidrun_driver_smoke.py
